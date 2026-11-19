import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../library/playlist_store.dart';
import '../../theme/colors.dart';
import '../keep_actions.dart' show onIphone;
import '../queue_toast.dart' show showPlaylistToast;
import '../tablet.dart' show onTablet;
import 'new_playlist_screen.dart';
import 'playlist_screen.dart' show PlaylistCover;

/// « Ajouter à une playlist » (maquette 15, écran B) pour [tracks] : on coche une ou plusieurs
/// playlists (ou on en crée une), puis OK. Une bulle dit « Ajouté à N playlists ».
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  final n = await Navigator.of(context, rootNavigator: true).push<int>(
    CupertinoPageRoute<int>(
      fullscreenDialog: true,
      builder: (_) => AddToPlaylistScreen(tracks: tracks),
    ),
  );
  if (n != null && n > 0 && context.mounted) showPlaylistToast(context, n);
}

/// « Déjà dans « Nom » » (maquette 15, écran D) pour [tracks], dont [dups] (leurs clés) sont
/// déjà dans la playlist [name] : true = ajouter quand même, false = ignorer (par défaut).
Future<bool> askDuplicate(
  BuildContext context, {
  required String name,
  required List<Track> tracks,
  required List<String> dups,
}) async {
  final s = AppScope.of(context).strings;
  final byKey = {for (final t in tracks) t.path: t};
  final body = tracks.length == 1
      ? s.alreadyInOne(byKey[dups.first]?.title ?? '')
      : s.alreadyInMany(dups.length, tracks.length);
  return askQuestion(
    context,
    title: s.alreadyInTitle(name),
    body: body,
    yes: s.addAnyway,
    no: s.ignore,
  );
}

/// La question de la maquette 15 (écran D) : titre, texte, deux boutons ; celui de droite,
/// rose, est le choix sûr ([no], par défaut). True : [yes].
Future<bool> askQuestion(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  required String no,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF232323),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFFBBBBBB),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    yes,
                    key: const Key('questionYes'),
                    onTap: () => Navigator.of(ctx).pop(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    no,
                    key: const Key('questionNo'),
                    primary: true,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return r ?? false;
}

class AddToPlaylistScreen extends StatefulWidget {
  const AddToPlaylistScreen({super.key, required this.tracks});
  final List<Track> tracks;
  @override
  State<AddToPlaylistScreen> createState() => _AddToPlaylistScreenState();
}

class _AddToPlaylistScreenState extends State<AddToPlaylistScreen> {
  final _search = TextEditingController();
  final _checked = <PlaylistRef>{};
  final _drafts = <NewPlaylist>[]; // made when OK is pressed, always ticked
  var _busy = false;
  String? _error;

  /// Playlists that got the songs, over every press of OK (a retry after an error too).
  var _done = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _keys => [for (final t in widget.tracks) t.path];

  Future<void> _new() async {
    final d = await askNewPlaylist(context);
    if (d == null || !mounted) return;
    setState(() => _drafts.add(d));
  }

  Future<void> _ok(List<ServerPlaylist> lists) async {
    if (_busy || (_checked.isEmpty && _drafts.isEmpty)) return;
    final app = AppScope.of(context);
    final store = app.playlistStore;
    final s = app.strings;
    final keys = _keys;
    setState(() {
      _busy = true;
      _error = null;
    });
    final names = {for (final p in lists) p.ref: p.name};
    // one question per playlist that already has some of these songs, none for the others
    final anyway = <PlaylistRef>{};
    for (final ref in _checked.toList()) {
      List<String> dups;
      try {
        dups = await store.duplicatesIn(ref, keys);
      } on Object {
        dups = const [];
      }
      if (dups.isEmpty) continue;
      if (!mounted) return;
      final yes = await askDuplicate(
        context,
        name: names[ref] ?? '',
        tracks: widget.tracks,
        dups: dups,
      );
      if (yes) anyway.add(ref);
    }
    var done = 0; // this round
    PlaylistProblem? problem;
    void fail(Object e) {
      problem ??= e is PlaylistWriteException
          ? e.problem
          : PlaylistProblem.failed;
    }

    for (final ref in _checked.toList()) {
      try {
        final n = await store.add(
          ref,
          keys,
          allowDuplicates: anyway.contains(ref),
        );
        if (n > 0) done++;
        _checked.remove(ref);
      } on Object catch (e) {
        fail(e);
      }
    }
    for (final d in _drafts.toList()) {
      try {
        await store.create(d.name, accountId: d.accountId, songs: keys);
        done++;
        _drafts.remove(d);
      } on Object catch (e) {
        fail(e);
        // it exists on the server anyway (only its songs failed): not made twice
        if (e is PlaylistWriteException && e.created != null) {
          _drafts.remove(d);
        }
      }
    }
    _done += done;
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop(_done);
      return;
    }
    setState(() {
      _busy = false;
      _error = s.playlistProblem(problem!);
    });
    if (done > 0) showPlaylistToast(context, _done);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final store = app.playlistStore;
    final q = sortKey(_search.text.trim());
    return Scaffold(
      backgroundColor: LafleurColors.bg,
      body: SafeArea(
        child: StreamBuilder<List<ServerPlaylist>>(
          stream: app.db.watchPlaylists(),
          builder: (context, snap) {
            return ValueListenableBuilder<Set<PlaylistRef>>(
              valueListenable: store.readOnlyPlaylists,
              builder: (context, _, _) {
                // a server playlist this account can't change is not offered
                final lists = [
                  for (final p in snap.data ?? const <ServerPlaylist>[])
                    if (store.canEdit(p.ref)) p,
                ];
                final shown = [
                  for (final p in lists)
                    if (q.isEmpty || sortKey(p.name).contains(q)) p,
                ];
                final drafts = [
                  for (final d in _drafts)
                    if (q.isEmpty || sortKey(d.name).contains(q)) d,
                ];
                final any = _checked.isNotEmpty || _drafts.isNotEmpty;
                return Column(
                  children: [
                    Container(
                      height: 50,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: LafleurColors.bar,
                        border: Border(bottom: BorderSide(color: Colors.black)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 40),
                            child: Image.asset(
                              'assets/logo-texte-grand.png',
                              height: 11,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: GestureDetector(
                              key: const Key('addCancel'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).pop(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Center(
                                  child: Text(
                                    s.cancel,
                                    style: const TextStyle(
                                      color: LafleurColors.pink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          children: [
                            const SizedBox(height: 6),
                            Text(
                              s.addToPlaylist,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            PillButton(
                              s.newPlaylistButton,
                              key: const Key('addNew'),
                              onTap: _new,
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: LafleurColors.bar,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: TextField(
                                key: const Key('addSearch'),
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                cursorColor: LafleurColors.pink,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  icon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: Color(0xFF888888),
                                  ),
                                  hintText: s.searchPlaylist,
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF888888),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 90,
                                ),
                                children: [
                                  for (final (i, d) in drafts.indexed)
                                    _Row(
                                      key: Key('draft-$i'),
                                      cover: null,
                                      name: d.name,
                                      sub: '${d.place} · ${s.newTag}',
                                      on: true,
                                      onTap: () =>
                                          setState(() => _drafts.remove(d)),
                                    ),
                                  for (final p in shown)
                                    _Row(
                                      key: Key('pl-${p.accountId}/${p.id}'),
                                      cover: PlaylistCover(
                                        ref: p.ref,
                                        tracks: p.covers,
                                        size: 44,
                                        radius: 4,
                                        stamp: p,
                                      ),
                                      name: p.name,
                                      sub:
                                          '${p.onPhone ? s.onMyDevice(onIphone, tablet: onTablet) : p.accountName} · ${s.nSongs(p.songCount)}',
                                      on: _checked.contains(p.ref),
                                      onTap: () => setState(() {
                                        _error = null;
                                        _checked.contains(p.ref)
                                            ? _checked.remove(p.ref)
                                            : _checked.add(p.ref);
                                      }),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          _error!,
                          key: const Key('addError'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18, top: 4),
                      child: PillButton(
                        s.okButton,
                        key: const Key('addOk'),
                        dim: !any || _busy,
                        onTap: () => _ok(lists),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.cover,
    required this.name,
    required this.sub,
    required this.on,
    required this.onTap,
  });
  final Widget? cover;
  final String name, sub;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: cover ?? const ColoredBox(color: Color(0xFF3A2240)),
            ),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            key: Key(on ? 'checked' : 'unchecked'),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? LafleurColors.pink : null,
              border: Border.all(
                color: on ? LafleurColors.pink : const Color(0xFF555555),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: on
                ? const Text(
                    '✓',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
        ],
      ),
    ),
  );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton(
    this.label, {
    super.key,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? LafleurColors.pink : null,
        border: Border.all(
          color: primary ? LafleurColors.pink : const Color(0xFF444444),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: primary ? const Color(0xFF111111) : LafleurColors.text,
        ),
      ),
    ),
  );
}
