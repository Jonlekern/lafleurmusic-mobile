import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/db.dart' show OfflineRow;
import '../library/models.dart';
import '../theme/colors.dart';
import 'keep_actions.dart';
import 'phone/keep_screen.dart';
import 'phone/phone_shell.dart' show pushPhone;

enum _Action { playNext, enqueue, keep, remove, select }

PopupMenuItem<_Action> _item(_Action a, String label) => PopupMenuItem(
  value: a,
  height: 36,
  child: Text(label, style: const TextStyle(fontSize: 14)),
);

/// Menu clic droit d'un morceau (maquette 8a).
Future<void> showTrackMenu(BuildContext context, Offset at, Track track) async {
  final app = AppScope.of(context);
  final s = app.strings;
  final a = await showMenu<_Action>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    color: const Color(0xFF232323),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFF3A3A3A)),
    ),
    items: [
      _item(_Action.playNext, s.playNextAction),
      _item(_Action.enqueue, s.addToQueue),
    ],
  );
  if (a == null || !context.mounted) return;
  switch (a) {
    case _Action.playNext:
      await app.player.playNext([track]);
    case _Action.enqueue:
      await app.player.enqueue([track]);
    case _Action.keep || _Action.remove || _Action.select:
      break; // seulement dans la feuille du téléphone
  }
}

/// Menu clic droit d'un album ou d'un artiste : ajouter tous ses morceaux, dans l'ordre.
Future<void> showTracksMenu(
  BuildContext context,
  Offset at,
  Future<List<Track>> Function() tracks,
) async {
  final app = AppScope.of(context);
  final s = app.strings;
  final a = await showMenu<_Action>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    color: const Color(0xFF232323),
    items: [
      _item(_Action.playNext, s.playNextAction),
      _item(_Action.enqueue, s.addToQueue),
    ],
  );
  if (a == null) return;
  final list = await tracks();
  if (a == _Action.playNext) {
    await app.player.playNext(list);
  } else {
    await app.player.enqueue(list);
  }
}

/// Une ligne de morceau : clic droit → menu.
class TrackMenuArea extends StatelessWidget {
  const TrackMenuArea({super.key, required this.track, required this.child});
  final Track track;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapUp: (d) => showTrackMenu(context, d.globalPosition, track),
    child: child,
  );
}

/// Téléphone (maquette 1, écran 4) : appui long → feuille du bas « Lire ensuite » / « Ajouter à la file »
/// pour [tracks] (un morceau, ou tout un album), puis « Garder sur mon iPhone » (ou « Retirer du téléphone »
/// quand tout est gardé) et « Sélectionner… » pour les morceaux d'un serveur. En-tête : [title] · [sub].
Future<void> showTrackSheet(
  BuildContext context, {
  required String title,
  String? sub,
  required Future<List<Track>> Function() tracks,
}) async {
  final app = AppScope.of(context);
  final s = app.strings;
  final list = await tracks();
  final remote = list.where(isRemote).toList();
  final rows = app.downloader == null || remote.isEmpty
      ? const <String, OfflineRow>{}
      : await app.db.watchOffline().first;
  final canKeep = app.downloader != null && remote.isNotEmpty;
  final allKept = canKeep && remote.every((t) => isKept(t, rows));
  if (!context.mounted) return;
  Widget option(BuildContext ctx, _Action a, String label, {bool hl = false}) =>
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(ctx).pop(a),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hl ? LafleurColors.pink : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: hl ? LafleurColors.ink : LafleurColors.text,
                fontWeight: hl ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
  final a = await showModalBottomSheet<_Action>(
    context: context,
    useRootNavigator: true, // par-dessus le mini-lecteur
    backgroundColor: const Color(0xFF232323),
    barrierColor: Colors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      side: BorderSide(color: Color(0xFF3A3A3A)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF555555),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text.rich(
                TextSpan(
                  text: title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    if (sub != null && sub.isNotEmpty)
                      TextSpan(
                        text: ' · $sub',
                        style: const TextStyle(
                          color: LafleurColors.sub,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            option(ctx, _Action.playNext, s.playNextAction, hl: true),
            option(ctx, _Action.enqueue, s.addToQueue),
            if (canKeep) ...[
              const Divider(
                color: Color(0xFF3A3A3A),
                height: 11,
                thickness: 1,
                indent: 4,
                endIndent: 4,
              ),
              allKept
                  ? option(ctx, _Action.remove, s.removeFromDevice(onIphone))
                  : option(ctx, _Action.keep, s.keepOnDevice(onIphone)),
              option(ctx, _Action.select, s.select),
            ],
          ],
        ),
      ),
    ),
  );
  if (a == null) return;
  switch (a) {
    case _Action.playNext:
      await app.player.playNext(list);
    case _Action.enqueue:
      await app.player.enqueue(list);
    case _Action.keep:
      if (context.mounted) await keepTracks(context, remote);
    case _Action.remove:
      if (context.mounted) await forgetTracks(context, remote);
    case _Action.select:
      if (context.mounted) {
        await pushPhone(
          context,
          KeepScreen(preselect: {for (final t in remote) t.album}),
        );
      }
  }
}

/// Glissement horizontal qui laisse le bord gauche au geste « retour » d'iOS.
class _NotFromEdge extends HorizontalDragGestureRecognizer {
  _NotFromEdge() : super();
  @override
  bool isPointerAllowed(PointerEvent event) =>
      event.position.dx > 24 && super.isPointerAllowed(event);
}

/// Téléphone : glisser une ligne vers la gauche → « Lire ensuite » (bandeau rose, maquette 1 écran 2).
class SwipeToPlayNext extends StatefulWidget {
  const SwipeToPlayNext({super.key, required this.track, required this.child});
  final Track track;
  final Widget child;

  /// Assez loin pour déclencher ; le bandeau ne dépasse pas [band].
  static const trigger = 80.0, band = 130.0;

  @override
  State<SwipeToPlayNext> createState() => _SwipeToPlayNextState();
}

class _SwipeToPlayNextState extends State<SwipeToPlayNext>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0, _from = 0; // décalage (négatif = vers la gauche)

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _end() {
    if (_dx <= -SwipeToPlayNext.trigger) {
      AppScope.of(context).player.playNext([widget.track]);
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final w = -_dx;
    final s = AppScope.of(context).strings;
    return RawGestureDetector(
      gestures: {
        _NotFromEdge: GestureRecognizerFactoryWithHandlers<_NotFromEdge>(
          _NotFromEdge.new,
          (r) {
            r.onStart = (_) => _back.stop();
            r.onUpdate = (d) => setState(
              () => _dx = (_dx + d.delta.dx).clamp(-SwipeToPlayNext.band, 0),
            );
            r.onEnd = (_) => _end();
            r.onCancel = _end;
          },
        ),
      },
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: w > 0 ? const Color(0xFF262626) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.child,
          ),
          if (w > 0)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LafleurColors.pink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: w >= 110
                    ? Text(
                        s.swipePlayNext,
                        maxLines: 1,
                        style: const TextStyle(
                          color: LafleurColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
