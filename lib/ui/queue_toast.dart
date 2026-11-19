import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../theme/colors.dart';
import 'phone/now_screen.dart' show openNowOn;

OverlayEntry? _shown;

void _hide() {
  final e = _shown;
  _shown = null;
  if (e == null) return;
  try {
    e.remove();
    e.dispose();
  } catch (_) {
    // l'écran (et son Overlay) est déjà parti : la bulle est partie avec lui
  }
}

/// La bulle « ✓ Ajouté à la file · Annuler · Voir la file » (maquette 13, écran A) : en bas, au-dessus du
/// mini-lecteur, et elle part seule après 4 s. Une nouvelle bulle remplace la précédente.
void showQueueToast(
  BuildContext context, {
  required int count,
  required VoidCallback onUndo,
  required VoidCallback onShowQueue,
}) {
  if (count <= 0) return;
  final overlay = Overlay.of(context);
  final app = AppScope.of(context);
  final s = app.strings;
  _hide();
  late final OverlayEntry entry;
  void done(VoidCallback act) {
    if (_shown == entry) _hide();
    act();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final inset = MediaQuery.paddingOf(ctx).bottom;
      // 76 au-dessus du mini-lecteur (fil 3 + 64), s'il y en a un
      final mini = app.player.current.track != null ? 67.0 : 0.0;
      return Positioned(
        left: 12,
        right: 12,
        bottom: inset + mini + 76,
        child: _Timed(
          onTimeout: () {
            if (_shown == entry) _hide();
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              key: const Key('queueToast'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                border: Border.all(color: const Color(0xFF3A3A3A)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 30,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.queueAdded,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LafleurColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Action(s.queueUndo, () => done(onUndo)),
                  const SizedBox(width: 12),
                  _Action(s.queueView, () => done(onShowQueue)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  _shown = entry;
  overlay.insert(entry);
}

/// Le minuteur de 4 s vit avec la bulle : l'écran qui disparaît l'emporte avec lui.
class _Timed extends StatefulWidget {
  const _Timed({required this.onTimeout, required this.child});
  final VoidCallback onTimeout;
  final Widget child;

  @override
  State<_Timed> createState() => _TimedState();
}

class _TimedState extends State<_Timed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onTimeout);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Text(
      label,
      style: const TextStyle(
        color: LafleurColors.pink,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Ajoute [tracks] à la fin de la file et dit « Ajouté à la file » : Annuler retire ces ajouts s'ils
/// attendent encore, Voir la file ouvre En cours sur À suivre. Rien n'est dit si rien n'a été ajouté
/// (un morceau absent de son compte n'entre pas dans la file).
Future<void> enqueueWithToast(BuildContext context, List<Track> tracks) async {
  final player = AppScope.of(context).player;
  final nav = Navigator.of(context);
  final playable = tracks.where((t) => !t.missing).toList();
  await player.enqueue(tracks);
  if (playable.isEmpty || !context.mounted) return;
  showQueueToast(
    context,
    count: playable.length,
    onUndo: () => player.removeAdded(playable),
    onShowQueue: () => openNowOn(nav),
  );
}
