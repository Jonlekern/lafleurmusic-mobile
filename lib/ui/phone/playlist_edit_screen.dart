import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../library/playlist_store.dart';
import '../../theme/colors.dart';
import '../cover_image.dart' show CoverEdge;
import '../keep_actions.dart' show onIphone;
import '../tablet.dart' show onTablet;
import 'add_to_playlist_sheet.dart' show askQuestion;
import 'playlist_screen.dart' show PlaylistCover;

/// The system photo picker (iOS PHPicker, Android photo picker: no permission asked); null
/// when nothing was chosen. Tests replace it.
@visibleForTesting
Future<File?> Function() pickPlaylistCover = () async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1200,
    maxHeight: 1200,
  );
  return x == null ? null : File(x.path);
};

/// What « Modifier » ended with.
sealed class EditOutcome {
  const EditOutcome();
}

/// The playlist was deleted: its screen closes too.
class PlaylistDeleted extends EditOutcome {
  const PlaylistDeleted();
}

/// A change did not go through (a server playlist): the message to tell.
class EditFailed extends EditOutcome {
  const EditFailed(this.message);
  final String message;
}

/// « Modifier » (maquette 15, écran E) : nom, pochette (playlists du téléphone), retirer (−),
/// déplacer (≡ à droite), « Supprimer la playlist » avec confirmation. Rien ne change avant
/// « OK » ; « Annuler » laisse tout comme avant.
Future<EditOutcome?> editPlaylist(
  BuildContext context,
  ServerPlaylist playlist,
  List<(String, Track?)> items,
) => Navigator.of(context, rootNavigator: true).push<EditOutcome>(
  CupertinoPageRoute<EditOutcome>(
    fullscreenDialog: true,
    builder: (_) => PlaylistEditScreen(playlist: playlist, items: items),
  ),
);

class PlaylistEditScreen extends StatefulWidget {
  const PlaylistEditScreen({
    super.key,
    required this.playlist,
    required this.items,
  });
  final ServerPlaylist playlist;

  /// The rows as the playlist screen shows them: (key, the row it plays or null: absent).
  final List<(String, Track?)> items;

  @override
  State<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

/// A row being edited: its position when the screen opened, and what it shows.
typedef _Row = ({int at, String key, Track? track});

class _PlaylistEditScreenState extends State<PlaylistEditScreen> {
  late final _name = TextEditingController(text: widget.playlist.name);
  late final List<_Row> _rows = [
    for (final (i, (k, t)) in widget.items.indexed) (at: i, key: k, track: t),
  ];
  File? _cover; // chosen, copied at OK
  var _busy = false;
  var _noName = false; // OK with an empty name: said under the field

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final File? f;
    try {
      f = await pickPlaylistCover();
    } on Object {
      return; // the picker could not open: nothing changes
    }
    if (f != null && mounted) setState(() => _cover = f);
  }

  Future<void> _ok() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final store = app.playlistStore;
    final ref = widget.playlist.ref;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _noName = true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (name != widget.playlist.name) {
        await store.rename(ref, name);
      }
      final kept = {for (final r in _rows) r.at};
      final gone = [
        for (var i = 0; i < widget.items.length; i++)
          if (!kept.contains(i)) i,
      ];
      if (gone.isNotEmpty) await store.remove(ref, gone);
      // the rows left, in their old order, then where each goes
      final left = [...kept]..sort();
      final order = [for (final r in _rows) left.indexOf(r.at)];
      if (!_isIdentity(order)) await store.reorder(ref, order);
      final cover = _cover;
      if (cover != null && ref is PhonePlaylistRef) {
        await store.setCover(ref, cover);
      }
    } on PlaylistWriteException catch (e) {
      if (mounted) {
        Navigator.of(context)
            .pop(EditFailed(app.strings.playlistProblem(e.problem)));
      }
      return;
    } on Object {
      if (mounted) {
        Navigator.of(
          context,
        ).pop(EditFailed(app.strings.playlistProblem(PlaylistProblem.failed)));
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  static bool _isIdentity(List<int> order) {
    for (var i = 0; i < order.length; i++) {
      if (order[i] != i) return false;
    }
    return true;
  }

  Future<void> _delete() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final s = app.strings;
    final p = widget.playlist;
    final yes = await askQuestion(
      context,
      title: s.deletePlaylistQuestion(p.name),
      body: s.deletePlaylistExplain(
        p.onPhone ? null : p.accountName,
        onIphone,
        tablet: onTablet,
      ),
      yes: s.deleteAction,
      no: s.cancel,
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await app.playlistStore.delete(p.ref);
    } on PlaylistWriteException catch (e) {
      if (mounted) {
        Navigator.of(context).pop(EditFailed(s.playlistProblem(e.problem)));
      }
      return;
    } on Object {
      if (mounted) {
        Navigator.of(context)
            .pop(EditFailed(s.playlistProblem(PlaylistProblem.failed)));
      }
      return;
    }
    // its .m3u8 goes at once (only ours); its songs stay kept, for themselves (Q6)
    await app.downloader?.syncPlaylists();
    if (mounted) Navigator.of(context).pop(const PlaylistDeleted());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final p = widget.playlist;
    final present = [for (final r in _rows) ?r.track];
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Bar(
              cancel: s.cancel,
              ok: s.okButton,
              onCancel: () => Navigator.of(context).pop(),
              onOk: _ok,
            ),
            Expanded(
              child: ReorderableListView(
                key: const Key('editRows'),
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                proxyDecorator: (child, _, _) => Material(
                  color: context.colors.bar,
                  borderRadius: BorderRadius.circular(8),
                  elevation: 8,
                  shadowColor: context.colors.shadow,
                  child: child,
                ),
                onReorderItem: (from, to) =>
                    setState(() => _rows.insert(to, _rows.removeAt(from))),
                header: Column(
                  children: [
                    GestureDetector(
                      key: const Key('editCover'),
                      behavior: HitTestBehavior.opaque,
                      onTap: p.onPhone ? _pickCover : null,
                      child: Column(
                        children: [
                          _cover != null
                              ? CoverEdge(
                                  radius: 6,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      _cover!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : PlaylistCover(
                                  ref: p.ref,
                                  tracks: present,
                                  size: 120,
                                ),
                          // a server's cover is never written: no choice for them
                          if (p.onPhone) ...[
                            const SizedBox(height: 6),
                            Text(
                              s.changeCover,
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        key: const Key('editName'),
                        controller: _name,
                        onChanged: (_) {
                          if (_noName) setState(() => _noName = false);
                        },
                        textAlign: TextAlign.center,
                        cursorColor: context.colors.pink,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.only(bottom: 4),
                          hintText: s.playlistName,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.colors.pink),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.colors.pink),
                          ),
                        ),
                      ),
                    ),
                    if (_noName)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          s.nameNeeded,
                          style: TextStyle(
                            color: context.colors.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
                footer: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Center(
                    child: GestureDetector(
                      key: const Key('editDelete'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _delete,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          s.deletePlaylist,
                          style: TextStyle(
                            color: context.colors.danger,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                children: [
                  for (final (i, r) in _rows.indexed)
                    _EditRow(
                      key: ValueKey('edit-${r.at}'),
                      index: i,
                      title: r.track?.title ?? s.missingSong,
                      sub: r.track == null
                          ? ''
                          : (r.track!.artist.isEmpty
                                ? s.unknownArtist
                                : r.track!.artist),
                      removeLabel: s.removeFromPlaylist,
                      moveLabel: s.moveSong,
                      onRemove: () => setState(() => _rows.removeAt(i)),
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

/// « Annuler » à gauche, le logo, « OK » à droite (maquette 15, écran E).
class _Bar extends StatelessWidget {
  const _Bar({
    required this.cancel,
    required this.ok,
    required this.onCancel,
    required this.onOk,
  });
  final String cancel, ok;
  final VoidCallback onCancel, onOk;

  Widget _button(
    BuildContext context,
    Key key,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.pink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.bar,
      border: Border(bottom: BorderSide(color: context.colors.hairline)),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Image.asset(context.logoAsset, height: 11),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _button(context, const Key('editCancel'), cancel, onCancel),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: _button(context, const Key('editOk'), ok, onOk),
        ),
      ],
    ),
  );
}

/// Une ligne : « − » rose (retirer), titre et artiste, « ≡ » à droite (tenir et glisser).
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.title,
    required this.sub,
    required this.removeLabel,
    required this.moveLabel,
    required this.onRemove,
  });
  final int index;
  final String title, sub, removeLabel, moveLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: removeLabel,
          child: GestureDetector(
            key: Key('editRemove-$index'),
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.pink,
                shape: BoxShape.circle,
              ),
              child: Text(
                '−',
                style: TextStyle(
                  color: context.colors.onPink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        ReorderableDragStartListener(
          index: index,
          child: Semantics(
            label: moveLabel,
            child: Padding(
              key: Key('editMove-$index'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 18,
                color: context.colors.textDimmer,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
