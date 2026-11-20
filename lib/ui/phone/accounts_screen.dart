import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../settings.dart';
import '../../sources/account_service.dart';
import '../../sources/accounts.dart';
import '../tablet.dart';
import '../../theme/colors.dart';
import 'account_form.dart';
import 'display_choice.dart';
import 'phone_shell.dart';
import 'plex_link_screen.dart';

/// Réglages → Comptes (maquette 2, écran 6) : les comptes dans l'ordre (glisser ⋮⋮), leur état,
/// « + Ajouter un compte », puis l'Affichage. Toucher un compte l'ouvre pour le modifier.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  StreamSubscription<List<Account>>? _sub;
  List<Account> _list = const [];
  final _headerCount = <String, int>{};
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _sub ??= app.accounts?.watch().listen((l) {
      if (!mounted) return;
      setState(() => _list = l);
      for (final a in l) {
        if (!_headerCount.containsKey(a.id)) {
          _headerCount[a.id] = 0;
          app.accounts!.headers(a.id).then((h) {
            if (mounted) setState(() => _headerCount[a.id] = h.length);
          }, onError: (Object _) {});
        }
      }
      // un test léger par compte à l'ouverture de l'écran, pas à chaque image
      if (!_checked) {
        _checked = true;
        app.accountService?.checkAll([for (final a in l) a.id]);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reorder(int from, int to) {
    final l = [..._list];
    l.insert(to, l.removeAt(from));
    setState(() => _list = l);
    AppScope.of(context).accounts?.reorder([for (final a in l) a.id]);
  }

  /// Après une modification de [a] : son nombre d'en-têtes est relu.
  Future<void> _edit(Account a) async {
    await pushPhone(context, AccountFormScreen(editing: a));
    if (!mounted) return;
    final h = await AppScope.of(context).accounts?.headers(a.id);
    if (mounted && h != null) setState(() => _headerCount[a.id] = h.length);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final service = app.accountService;
    final mode = app.settings?.displayMode ?? DisplayMode.all;
    return PhoneScaffold(
      mini: false,
      // pas encore d'écran Réglages : ⚙︎ ouvre directement les comptes
      header: PhoneHeader(back: onTablet ? s.back : s.home),
      body: ListenableBuilder(
        listenable: service ?? const _NoListenable(),
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Row(
                    children: [
                      Text(s.myAccounts, style: _secStyle(context)),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${s.dragHint} '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: 12,
                                color: context.colors.textFaint,
                              ),
                            ),
                            TextSpan(text: ' ${s.toReorder}'),
                          ],
                        ),
                        style: _secStyle(context)
                            .copyWith(color: context.colors.textFaint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverReorderableList(
                itemCount: _list.length,
                onReorderItem: _reorder,
                proxyDecorator: (child, _, _) =>
                    Material(type: MaterialType.transparency, child: child),
                itemBuilder: (context, i) {
                  final a = _list[i];
                  return _AccountRow(
                    key: ValueKey(a.id),
                    index: i,
                    account: a,
                    headers: _headerCount[a.id] ?? 0,
                    state: service?.stateOf(a.id),
                    onTap: () => _edit(a),
                    onRelink: () =>
                        pushPhone(context, PlexLinkScreen(relink: a)),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
              sliver: SliverList.list(
                children: [
                  // un compte Plex coupé : la musique gardée reste (maquette 14 D)
                  if (_list.any(
                    (a) => service?.stateOf(a.id) == AccountState.relink,
                  ))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
                      child: Text(
                        s.plexKeptStillPlays,
                        style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                  _WidePill(
                    label: s.addAccount,
                    onTap: () => pushPhone(context, const AccountFormScreen()),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                    child: Text(s.display, style: _secStyle(context)),
                  ),
                  // Mode normal / Mode Classic (maquette 12 C) : le téléphone seulement
                  if (app.classicMode case final classic?
                      when !onTablet &&
                          AdaptiveHome.isPhone(MediaQuery.sizeOf(context)))
                    ClassicModeChoice(mode: classic),
                  DisplaySegment(
                    value: mode,
                    onChanged: (m) {
                      app.chooseDisplay(m, order: _list);
                      setState(() {});
                    },
                  ),
                  // « Perso » : les comptes à mélanger
                  if (mode == DisplayMode.custom) ...[
                    const SizedBox(height: 12),
                    for (final a in _list)
                      _Check(
                        key: ValueKey('check-${a.id}'),
                        label: a.name,
                        on: app.settings!.customAccounts.contains(a.id),
                        onTap: () {
                          app.toggleCustom(a.id, _list);
                          setState(() {});
                        },
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    s.sameAlbumNote(
                      defaultTargetPlatform == TargetPlatform.iOS,
                      tablet: onTablet,
                    ),
                    style: phoneHint(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _secStyle(BuildContext context) => TextStyle(
  color: context.colors.textMuted,
  fontSize: 11,
  letterSpacing: 1,
  fontWeight: FontWeight.w700,
);

class _NoListenable implements Listenable {
  const _NoListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// Un compte : ⋮⋮ (glisser pour l'ordre), initiale en couleur, nom, type · adresse, état, ›.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.index,
    required this.account,
    required this.headers,
    required this.state,
    required this.onTap,
    this.onRelink,
  });
  final int index;
  final Account account;
  final int headers;
  final AccountState? state;
  final VoidCallback onTap;

  /// « Nouveau code » d'un compte « À reconnecter ».
  final VoidCallback? onRelink;

  static Color colorOf(BuildContext context, AccountType t) => switch (t) {
    AccountType.subsonic => context.colors.pink,
    AccountType.jellyfin => context.colors.jellyfin,
    AccountType.plex => context.colors.plex,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final a = account;
    final host = a.base.hasPort ? '${a.base.host}:${a.base.port}' : a.base.host;
    final sub =
        '${s.typeName(a.type)} · ${headers > 0 ? s.nHeaders(headers) : host}';
    final st = state;
    // jeton retiré (Plex) : bord rose, « À reconnecter », « Nouveau code » (maquette 14 D)
    final relink = st == AccountState.relink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: relink
              ? BorderSide(color: context.colors.pink)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    key: ValueKey('grip-${a.id}'),
                    color: Colors.transparent,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: context.colors.textFaint,
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorOf(context, a.type),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    a.name.isEmpty
                        ? '?'
                        : a.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: context.colors.onPink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
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
                        relink ? s.plexRelink : sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: relink
                            ? TextStyle(
                                color: context.colors.pink,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              )
                            : TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (relink)
                  _Chip(label: s.plexNewCode, onTap: onRelink)
                else if (st != null)
                  Text(
                    s.accountState(st),
                    style: TextStyle(
                      color: st == AccountState.connected
                          ? context.colors.ok
                          : context.colors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                if (!relink) ...[
                  const SizedBox(width: 10),
                  Text(
                    '›',
                    style: TextStyle(
                      color: context.colors.textFaint,
                      fontSize: 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Petite pilule à contour rose (« Nouveau code »).
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.pink),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.pink,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Pilule grise sur toute la largeur (« + Ajouter un compte »).
class _WidePill extends StatelessWidget {
  const _WidePill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// Case à cocher rose de la maquette (✓ sur fond rose).
class _Check extends StatelessWidget {
  const _Check({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on ? context.colors.text : context.colors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Un compte / Tout / Perso.
class DisplaySegment extends StatelessWidget {
  const DisplaySegment({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DisplayMode value;
  final ValueChanged<DisplayMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return PhoneSegment<DisplayMode>(
      value: value,
      onChanged: onChanged,
      options: [
        SegmentOption(DisplayMode.one, s.oneAccount),
        SegmentOption(DisplayMode.all, s.allAccounts),
        SegmentOption(DisplayMode.custom, s.customDisplay),
      ],
    );
  }
}

/// Mode normal / Mode Classic et sa légende (maquette 12 C). Changer remplace la vue
/// téléphone à chaud ; le lecteur et la file ne bougent pas.
class ClassicModeChoice extends StatelessWidget {
  const ClassicModeChoice({super.key, required this.mode});
  final ValueNotifier<bool> mode;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: mode,
            builder: (_, on, _) => PhoneSegment<bool>(
              value: on,
              onChanged: (v) => mode.value = v,
              options: [
                SegmentOption(false, s.normalMode),
                SegmentOption(true, s.classicMode),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(s.classicModeNote, style: phoneHint(context)),
          ),
        ],
      ),
    );
  }
}
