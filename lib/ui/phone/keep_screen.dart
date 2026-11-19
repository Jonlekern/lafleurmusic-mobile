import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../library/db.dart' show OfflineRow;
import '../../library/merge.dart';
import '../../library/models.dart';
import '../../offline/downloader.dart' show KeepOrigin, unknownTrackSize;
import '../../settings.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../tablet.dart';
import '../keep_actions.dart';
import 'home_screen.dart' show PhoneSection;
import 'phone_shell.dart';

/// Un album de l'écran : ses morceaux de serveur, ce qu'il pèse, s'il est déjà là.
class _Entry {
  _Entry(this.album, this.tracks);
  final Album album;
  final List<Track> tracks;

  int get durationMs => tracks.fold(0, (m, t) => m + t.durationMs);

  /// Octets, ou null si le serveur n'a donné aucune taille.
  int? get bytes => tracks.any((t) => t.size > 0)
      ? tracks.fold<int>(
          0,
          (m, t) => m + (t.size > 0 ? t.size : unknownTrackSize),
        )
      : null;
}

/// « Sélectionner » → « Garder sur mon iPhone » (maquette 2, écran 8) : des albums à cocher, la place
/// qu'ils prennent, et le bouton qui les met en file. [preselect] : albums déjà cochés.
class KeepScreen extends StatefulWidget {
  const KeepScreen({super.key, this.preselect = const {}});
  final Set<String> preselect;

  @override
  State<KeepScreen> createState() => _KeepScreenState();
}

class _KeepScreenState extends State<KeepScreen> {
  List<_Entry>? _entries;
  Map<String, OfflineRow> _rows = const {};
  int _used = 0;
  late final Set<String> _selected = {...widget.preselect};
  StreamSubscription<Map<String, OfflineRow>>? _sub;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final db = AppScope.of(context).db;
    unawaited(_load());
    _sub = db.watchOfflineWithTwins().listen((m) async {
      final used = await db.offlineBytes();
      if (mounted) {
        setState(() {
          _rows = m;
          _used = used;
        });
      }
    });
  }

  Future<void> _load() async {
    final library = AppScope.of(context).library;
    final albums = await library.albums().first;
    final all = await library.allTracks().first;
    final by = <String, List<Track>>{};
    for (final t in all.where(isRemote)) {
      (by[albumKeyOf(t)] ??= []).add(t);
    }
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final a in albums)
          if (by[a.key] != null) _Entry(a, by[a.key]!),
      ];
    });
  }

  /// Tous les morceaux de ce serveur sont déjà là (finis).
  bool _done(_Entry e) =>
      e.tracks.every((t) => _rows[t.path]?.state == OfflineState.done.name);

  /// Ce qu'il faut encore télécharger (hors morceaux déjà finis ou en file).
  int _need(Iterable<_Entry> es) => [
    for (final e in es)
      for (final t in e.tracks)
        if (!isKept(t, _rows)) t.size > 0 ? t.size : unknownTrackSize,
  ].fold(0, (a, b) => a + b);

  Future<void> _keep(List<_Entry> chosen) async {
    setState(() => _busy = true);
    final ok = await keepTracks(context, [
      for (final e in chosen) ...e.tracks,
    ], origin: KeepOrigin.albumOf);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final entries = _entries ?? const <_Entry>[];
    final chosen = [
      for (final e in entries)
        if (_selected.contains(e.album.name) && !_done(e)) e,
    ];
    final need = _need(chosen);
    final limit =
        app.settings?.storageLimitBytes ?? AppSettings.defaultStorageLimitBytes;
    final gauge = limit <= 0 ? 0.0 : (_used / limit).clamp(0.0, 1.0);
    return PhoneScaffold(
      mini: false,
      header: PhoneHeader(
        leading: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
              children: [
                PhoneSection(s.albumsSelected(chosen.length)),
                for (final e in entries) _row(e, s),
                const SizedBox(height: 10),
                PhoneSection(s.spaceOnDevice(onIphone, tablet: onTablet)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text.rich(
                    TextSpan(
                      text: s.usedOf(s.size(_used), s.size(limit)),
                      children: [
                        if (need > 0)
                          TextSpan(
                            text: ' · + ${s.size(need)}',
                            style: const TextStyle(color: LafleurColors.pink),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFCCCCCC),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: gauge,
                      minHeight: 8,
                      color: LafleurColors.pink,
                      backgroundColor: const Color(0xFF2A2A2A),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(
                    s.filesHint(onIphone, tablet: onTablet),
                    style: const TextStyle(
                      color: LafleurColors.sub,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _KeepButton(
              label: s.keepButton(
                onIphone,
                need > 0 ? s.size(need) : null,
                tablet: onTablet,
              ),
              onTap: chosen.isEmpty || _busy ? null : () => _keep(chosen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_Entry e, Strings s) {
    final done = _done(e);
    final on = _selected.contains(e.album.name) && !done;
    final bytes = e.bytes;
    final info =
        '${s.minutes(e.durationMs ~/ 60000)} · ${bytes == null ? '—' : s.size(bytes)}';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: done
            ? null
            : () => setState(
                () => on
                    ? _selected.remove(e.album.name)
                    : _selected.add(e.album.name),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              _Check(on: on),
              const SizedBox(width: 12),
              CoverImage(trackPath: e.album.coverTrackPath, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.album.name.isEmpty ? s.unknownArtist : e.album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (done) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_downward_rounded,
                        size: 14,
                        color: LafleurColors.pink,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                done ? s.alreadyKept : info,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: on ? LafleurColors.pink : null,
      border: Border.all(
        color: on ? LafleurColors.pink : const Color(0xFF555555),
        width: 2,
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: on
        ? const Icon(Icons.check_rounded, size: 15, color: LafleurColors.ink)
        : null,
  );
}

/// Grand bouton rose du bas (maquette 2, écran 8).
class _KeepButton extends StatelessWidget {
  const _KeepButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.4 : 1,
    child: Material(
      color: LafleurColors.pink,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.arrow_downward_rounded,
                size: 16,
                color: LafleurColors.ink,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LafleurColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
