import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../sources/accounts.dart';
import '../../sources/plex_link.dart';
import '../../theme/colors.dart';
import 'phone_shell.dart';

/// plex.tv/link, ouvert par « Ouvrir plex.tv/link ».
final plexLinkPage = Uri.parse('https://plex.tv/link');

Future<bool> _openInBrowser(Uri u) =>
    launchUrl(u, mode: LaunchMode.externalApplication);

/// Connexion à Plex par un code (maquette 14, écrans B et C) : le code à taper sur
/// plex.tv/link, l'attente, puis le choix du serveur (sauté s'il n'y en a qu'un).
/// [relink] : « Nouveau code » d'un compte « À reconnecter » ; son jeton est remplacé sur place.
/// Ferme avec `true` une fois le compte enregistré.
class PlexLinkScreen extends StatefulWidget {
  const PlexLinkScreen({
    super.key,
    this.name = '',
    this.relink,
    this.link,
    this.openUrl,
  });

  /// Nom tapé dans le formulaire ; vide : le nom du serveur.
  final String name;
  final Account? relink;

  /// plex.tv déjà prêt (tests) ; sinon le service de comptes en fait un (fermé en sortant).
  final PlexLink? link;

  /// Ouvre une adresse dans le navigateur (tests : rien n'est ouvert).
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<PlexLinkScreen> createState() => _PlexLinkScreenState();
}

enum _Step { asking, waiting, expired, failed, finding, choosing, saving }

class _PlexLinkScreenState extends State<PlexLinkScreen> {
  PlexLink? _link;
  bool _ownsLink = false;
  _Step _step = _Step.asking;
  PlexPin? _pin;
  PinWait? _wait;
  String? _error;
  String? _token; // jeton du compte plex.tv : jamais affiché ni journalisé
  String? _user; // qui est ce compte sur plex.tv (uuid)
  List<(PlexServer, PlexProbe)> _servers = const [];
  int _chosen = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  @override
  void dispose() {
    // l'attente s'arrête avec l'écran : plus aucune requête, aucun minuteur
    _wait?.cancel();
    _wait = null;
    if (_ownsLink) _link?.close();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _error = message;
    });
  }

  Future<PlexLink?> _plexLink() async {
    final l = _link ?? widget.link;
    if (l != null) return _link = l;
    final service = AppScope.of(context).accountService;
    if (service == null) return null;
    final made = await service.newPlexLink();
    if (!mounted) {
      made.close();
      return null;
    }
    _ownsLink = true;
    return _link = made;
  }

  /// Un code neuf (au début, et « Nouveau code »).
  Future<void> _start() async {
    final s = AppScope.of(context).strings;
    _wait?.cancel();
    _wait = null;
    // first call: already so (no setState while the first build runs)
    if (_step != _Step.asking || _pin != null || _error != null) {
      setState(() {
        _step = _Step.asking;
        _error = null;
        _pin = null;
      });
    }
    final PlexLink? link;
    final PlexPin pin;
    try {
      link = await _plexLink();
      if (link == null) return;
      pin = await link.requestPin();
    } on Object {
      _fail(s.plexTvUnreachable);
      return;
    }
    if (!mounted) return;
    final wait = link.poll(pin);
    setState(() {
      _pin = pin;
      _wait = wait;
      _step = _Step.waiting;
    });
    final token = await wait.token;
    if (!mounted || !identical(wait, _wait)) return;
    if (token == null) {
      if (wait.expired) setState(() => _step = _Step.expired);
      return;
    }
    _token = token;
    await _found(link, token);
  }

  /// Le code a été tapé : les serveurs du compte, où ils répondent.
  Future<void> _found(PlexLink link, String token) async {
    final app = AppScope.of(context);
    final s = app.strings;
    setState(() => _step = _Step.finding);
    final List<PlexServer> servers;
    try {
      _user = await link.user(token);
      servers = await link.servers(token);
    } on Object {
      _fail(s.plexTvUnreachable);
      return;
    }
    if (!mounted) return;
    final relink = widget.relink;
    if (relink != null) {
      // un code d'un autre compte Plex ne remplace rien
      String? before;
      try {
        before = await app.accounts?.plexUser(relink.id);
      } on Object {
        before = null;
      }
      if (!mounted) return;
      if (before != null && before != _user) {
        _fail(s.plexOtherAccount);
        return;
      }
      // le même serveur, sinon ses morceaux ne seraient plus les mêmes
      PlexServer? same;
      try {
        final mine = await app.accounts?.plexServer(relink.id);
        same = servers.where((v) => v.machineId == mine?.machineId).firstOrNull;
      } on Object {
        same = null;
      }
      if (!mounted) return;
      if (same == null) {
        _fail(s.plexServerGone);
        return;
      }
      final probe = await link.probe(same, token: token);
      if (!mounted) return;
      await _save(same, probe);
      return;
    }
    if (servers.isEmpty) {
      _fail(s.plexNoServer);
      return;
    }
    final probes = await Future.wait([
      for (final v in servers) link.probe(v, token: token),
    ]);
    if (!mounted) return;
    final found = [for (final (i, v) in servers.indexed) (v, probes[i])];
    if (found.length == 1) {
      await _save(found.single.$1, found.single.$2);
      return;
    }
    // choisi d'avance : celui de la maison, sinon le premier qui répond
    var pick = found.indexWhere((e) => e.$2.connection?.local == true);
    if (pick < 0) pick = found.indexWhere((e) => e.$2.connection != null);
    setState(() {
      _servers = found;
      _chosen = pick < 0 ? 0 : pick;
      _step = _Step.choosing;
    });
  }

  Future<void> _save(PlexServer server, PlexProbe probe) async {
    final app = AppScope.of(context);
    final s = app.strings;
    final service = app.accountService;
    final userToken = _token;
    final base =
        probe.connection?.uri ??
        orderConnections(server.connections).firstOrNull?.uri;
    if (base == null) {
      _fail(s.plexNoAddress);
      return;
    }
    if (service == null || userToken == null) {
      _fail(s.saveFailed);
      return;
    }
    setState(() => _step = _Step.saving);
    // un serveur partagé a son propre jeton
    final token = server.accessToken ?? userToken;
    try {
      final relink = widget.relink;
      if (relink != null) {
        await service.relinkPlex(
          relink.id,
          server: server,
          token: token,
          base: base,
          accountToken: userToken,
          plexUser: _user,
        );
      } else {
        await service.addPlex(
          name: widget.name.trim().isNotEmpty
              ? widget.name.trim()
              : server.name,
          server: server,
          token: token,
          base: base,
          accountToken: userToken,
          plexUser: _user,
        );
      }
    } on Object {
      _fail(s.saveFailed);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _copy() async {
    final pin = _pin;
    if (pin == null) return;
    await Clipboard.setData(ClipboardData(text: pin.code));
  }

  Future<void> _open() async {
    try {
      await (widget.openUrl ?? _openInBrowser)(plexLinkPage);
    } on Object {
      // pas de navigateur : le code reste à taper à la main
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return PhoneScaffold(
      mini: false,
      header: PhoneHeader(back: _step == _Step.choosing ? s.back : s.cancel),
      body: _step == _Step.choosing ? _choice(context) : _code(context),
    );
  }

  /// Écran B : le code, les deux boutons, l'attente (ou « Code expiré »).
  Widget _code(BuildContext context) {
    final s = AppScope.of(context).strings;
    final pin = _pin;
    final found = _step == _Step.finding || _step == _Step.saving;
    final dead = _step == _Step.expired || _step == _Step.failed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        const SizedBox(height: 30),
        Text(
          found ? s.plexDone : s.plexYourCode,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (pin != null && !found) ...[
          const SizedBox(height: 22),
          _CodeBoxes(code: pin.code, dim: dead),
        ],
        if (pin != null && !dead && !found) ...[
          const SizedBox(height: 22),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: s.plexGoTo),
                TextSpan(
                  text: s.plexLinkSite,
                  style: TextStyle(
                    color: context.colors.textHighlight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: s.plexTypeIt),
              ],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
            child: BigButton(label: s.plexOpenLink, onTap: _open),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: BigButton(
              key: const ValueKey('plex-copy'),
              label: s.plexCopyCode,
              outline: true,
              onTap: _copy,
            ),
          ),
        ],
        if (dead) ...[
          const SizedBox(height: 34),
          Text(
            _step == _Step.expired ? s.plexCodeExpired : (_error ?? ''),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.danger,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
            child: BigButton(label: s.plexNewCode, onTap: _start),
          ),
        ] else ...[
          const SizedBox(height: 34),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: context.colors.pink,
                  backgroundColor: context.colors.divider,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                found ? s.plexSearching : s.plexWaiting,
                style: TextStyle(color: context.colors.textLabel, fontSize: 14),
              ),
            ],
          ),
          if (!found) ...[
            const SizedBox(height: 8),
            Text(
              s.plexCodeLasts,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ],
    );
  }

  /// Écran C : plusieurs serveurs, lequel ?
  Widget _choice(BuildContext context) {
    final s = AppScope.of(context).strings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            s.plexDone,
            style: TextStyle(
              color: context.colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            s.plexWhichServer(_servers.length),
            style: TextStyle(color: context.colors.textMuted, fontSize: 12),
          ),
        ),
        for (final (i, (server, probe)) in _servers.indexed)
          _ServerRow(
            key: ValueKey('plex-server-$i'),
            name: server.name,
            sub: _where(s, probe),
            on: i == _chosen,
            onTap: () => setState(() => _chosen = i),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: BigButton(
            label: s.plexAdd,
            onTap: () {
              final (server, probe) = _servers[_chosen];
              _save(server, probe);
            },
          ),
        ),
      ],
    );
  }

  static String _where(Strings s, PlexProbe p) {
    final c = p.connection;
    if (c == null) return s.plexNoAnswer;
    final place = c.local ? s.plexAtHome : s.plexOverInternet;
    final n = p.musicLibraries;
    return n == null ? place : '$place · ${s.plexMusicLibraries(n)}';
  }
}

/// Les caractères du code, chacun dans sa case (maquette 14 B).
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.code, this.dim = false});
  final String code;
  final bool dim;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final (i, ch) in code.characters.indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Container(
          width: 62,
          height: 78,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.bar,
            border: Border.all(color: context.colors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ch,
            style: TextStyle(
              color: dim ? context.colors.outlineDim : context.colors.pink,
              fontSize: 40,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ],
  );
}

/// Un serveur du compte : P orange (choisi) ou gris, nom, où il répond, case à cocher.
class _ServerRow extends StatelessWidget {
  const _ServerRow({
    super.key,
    required this.name,
    required this.sub,
    required this.on,
    required this.onTap,
  });
  final String name, sub;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.field,
          border: Border.all(
            color: on ? context.colors.pink : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            PlexInitial(
              color: on ? context.colors.plex : context.colors.outlineDim,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? context.colors.pink : null,
                border: Border.all(
                  color: on ? context.colors.pink : context.colors.outlineDim,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: on
                  ? Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: context.colors.onPink,
                    )
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Le « P » de Plex dans son carré arrondi.
class PlexInitial extends StatelessWidget {
  const PlexInitial({super.key, this.color});
  final Color? color; // orange Plex par défaut

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color ?? context.colors.plex,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'P',
      style: TextStyle(
        color: context.colors.onPink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Grand bouton rose sur toute la largeur (maquette 14) ; [outline] : contour rose.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.outline = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool outline;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: outline ? null : context.colors.pink,
          border: Border.all(color: context.colors.pink),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: outline ? context.colors.pink : context.colors.onPink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
