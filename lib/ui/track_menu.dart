import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';

enum _Action { playNext, enqueue }

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
