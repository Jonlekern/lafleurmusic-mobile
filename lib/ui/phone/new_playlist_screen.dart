import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme/colors.dart';
import '../keep_actions.dart' show onIphone;
import '../tablet.dart' show onTablet;

/// A playlist to make: its [name], and where ([accountId] null: on the phone) with that
/// place's name for the lists ([place]).
class NewPlaylist {
  const NewPlaylist(this.name, this.accountId, this.place);
  final String name;
  final String? accountId;
  final String place;
}

/// Donner un nom (maquette 15, écran C) : le nom, « Où la ranger : » (le téléphone, ou un compte
/// qui laisse créer des playlists) et Annuler / Créer. Sans aucun compte (ou aucun où ranger),
/// la ligne « Où la ranger » n'est pas là : la playlist reste sur le téléphone.
/// Rend la [NewPlaylist] (rien n'est créé ici), ou rien si on annule.
Future<NewPlaylist?> askNewPlaylist(BuildContext context) =>
    Navigator.of(context).push(
      CupertinoPageRoute<NewPlaylist>(
        builder: (_) => const NewPlaylistScreen(),
      ),
    );

class NewPlaylistScreen extends StatefulWidget {
  const NewPlaylistScreen({super.key});
  @override
  State<NewPlaylistScreen> createState() => _NewPlaylistScreenState();
}

class _NewPlaylistScreenState extends State<NewPlaylistScreen> {
  final _name = TextEditingController();
  // (account id or null for the phone, label)
  List<(String?, String)> _places = const [];
  String? _where; // the chosen account id; null: the phone
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final s = app.strings;
    final places = <(String?, String)>[
      (null, s.onMyDevice(onIphone, tablet: onTablet)),
    ];
    final accounts = await app.accounts?.watch().first ?? const [];
    final store = app.playlistStore;
    for (final a in accounts) {
      if (await store.canWrite(a.id)) places.add((a.id, a.name));
    }
    if (!mounted) return;
    // nothing to choose from (no account, or none that lets us write): the phone, silently
    setState(() => _places = places.length > 1 ? places : const []);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final s = AppScope.of(context).strings;
    final place = _places.where((p) => p.$1 == _where).firstOrNull;
    Navigator.of(context).pop(
      NewPlaylist(
        n,
        _where,
        place?.$2 ?? s.onMyDevice(onIphone, tablet: onTablet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final ready = _name.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.colors.pinkTint, context.colors.bg],
          stops: [0, 0.6],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.nameYourPlaylist,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 26),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: context.colors.pink,
                          width: 2,
                        ),
                      ),
                    ),
                    child: TextField(
                      key: const Key('newPlaylistName'),
                      controller: _name,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _create(),
                      cursorColor: context.colors.pink,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 8),
                      ),
                    ),
                  ),
                  if (_places.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      s.whereToKeep,
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Seg(
                      places: _places,
                      value: _where,
                      onChanged: (v) => setState(() => _where = v),
                    ),
                  ],
                  const SizedBox(height: 34),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PillButton(
                        s.cancel,
                        outlined: true,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      PillButton(
                        s.createButton,
                        key: const Key('newPlaylistCreate'),
                        dim: !ready,
                        onTap: _create,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.places,
    required this.value,
    required this.onChanged,
  });
  final List<(String?, String)> places;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget cell((String?, String) p) {
      final on = p.$1 == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(p.$1),
        child: Container(
          key: Key('where-${p.$1 ?? 'phone'}'),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? context.colors.pink : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            p.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? context.colors.ink : context.colors.textLabel,
            ),
          ),
        ),
      );
    }

    final few = places.length <= 3;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.field,
        borderRadius: BorderRadius.circular(9),
      ),
      child: few
          ? Row(
              children: [
                // as wide as their text (« Sur mon iPhone » is the longest)
                for (final p in places)
                  Expanded(flex: p.$2.length, child: cell(p)),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final p in places) cell(p)]),
            ),
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton(
    this.label, {
    super.key,
    required this.onTap,
    this.outlined = false,
    this.dim = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool outlined, dim;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? 0.4 : 1,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: dim ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : context.colors.pink,
          border: outlined
              ? Border.all(color: context.colors.outlineDim)
              : null,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: outlined ? context.colors.textBright : context.colors.onPink,
          ),
        ),
      ),
    ),
  );
}
