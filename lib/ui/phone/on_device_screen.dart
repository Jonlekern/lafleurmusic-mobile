import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../library/db.dart' show OfflineRow;
import '../../library/models.dart';
import '../../offline/device.dart';
import '../../offline/downloader.dart'
    show Downloader, KeepResult, unknownTrackSize;
import '../../offline/paths.dart' show fileOrPlaceholderExists;
import '../../settings.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../keep_actions.dart';
import 'home_screen.dart' show PhoneSection;
import 'phone_shell.dart';

enum _Missing { cancel, find, adopt }

const _gib = 1024 * 1024 * 1024;
const _red = Color(0xFFFF6B6B);
const _dim = Color(0xFF666666);

/// Un album gardé (ou en partie) : ce qui est fini, ce que ça pèse.
class _Kept {
  _Kept(this.name, this.coverPath);
  final String name;
  final String? coverPath;
  final paths =
      <String>[]; // les copies finies ou en file : ce que « Retirer » oublie
  int done = 0, bytes = 0, durationMs = 0;
  bool top100Only = true, full = false;
}

/// Un album dont des morceaux ont été refusés.
class _Failed {
  _Failed(this.name, this.coverPath);
  final String name;
  final String? coverPath;
  final byReason = <OfflineReason, List<String>>{};
}

class _Data {
  const _Data({
    this.queued = const [],
    this.kept = const [],
    this.failed = const [],
    this.used = 0,
    this.tracks = const {},
  });
  final List<OfflineRow> queued; // dans l'ordre de départ
  final List<_Kept> kept;
  final List<_Failed> failed;
  final int used;
  final Map<String, Track> tracks;
}

/// « Sur mon iPhone » (maquette 4) : le téléchargement en cours, les albums gardés, les échecs à
/// réessayer, la place, la limite et le dossier des copies.
class OnDeviceScreen extends StatefulWidget {
  const OnDeviceScreen({super.key});

  @override
  State<OnDeviceScreen> createState() => _OnDeviceScreenState();
}

class _OnDeviceScreenState extends State<OnDeviceScreen> {
  _Data _data = const _Data();
  final _tracks = <String, Track>{};
  StreamSubscription<_Data>? _sub;
  int?
  _free; // place libre + copies, en octets ; null tant qu'on ne la connaît pas
  int? _dragGb; // la limite pendant que le doigt glisse
  String?
  _folder; // dossier choisi (deux derniers noms) ; null = celui par défaut
  bool _moving = false; // le déplacement tourne (le bouton le dit)
  bool _busy = false; // sélecteur ouvert ou déplacement : un seul à la fois
  bool _loadingSpace = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final db = AppScope.of(context).db;
    _sub = db.watchOffline().asyncMap(_build).listen((d) {
      if (mounted) setState(() => _data = d);
      unawaited(_loadSpace(d.used));
    });
    unawaited(_loadFolder());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<_Data> _build(Map<String, OfflineRow> rows) async {
    final db = AppScope.of(context).db;
    for (final r in rows.keys) {
      if (_tracks.containsKey(r)) continue;
      final t = await db.trackByPath(r);
      if (t != null) _tracks[r] = t;
    }
    final fullAlbums = await db.watchKeptAlbums().first;
    final used = await db.offlineBytes();
    final sorted = rows.values.toList()
      ..sort((a, b) {
        final c = a.addedAt.compareTo(b.addedAt);
        return c != 0 ? c : a.trackPath.compareTo(b.trackPath);
      });
    final queued = <OfflineRow>[];
    final kept = <String, _Kept>{};
    final failed = <String, _Failed>{};
    for (final r in sorted) {
      final t = _tracks[r.trackPath];
      if (t == null) continue; // le morceau a quitté la bibliothèque
      switch (r.state) {
        case 'queued':
          queued.add(r);
          (kept[t.album] ??= _Kept(t.album, t.path)).paths.add(r.trackPath);
        case 'done':
          final k = kept[t.album] ??= _Kept(t.album, t.path);
          k.paths.add(r.trackPath);
          k.done++;
          k.bytes += r.size;
          k.durationMs += t.durationMs;
          if (r.reason != OfflineReason.top100.name) k.top100Only = false;
        case 'failed':
          final f = failed[t.album] ??= _Failed(t.album, t.path);
          final reason = r.reason == OfflineReason.top100.name
              ? OfflineReason.top100
              : OfflineReason.user;
          (f.byReason[reason] ??= []).add(r.trackPath);
      }
    }
    return _Data(
      queued: queued,
      kept: [
        for (final k in kept.values)
          if (k.done > 0) k..full = fullAlbums.contains(k.name),
      ],
      failed: failed.values.toList(),
      used: used,
      tracks: Map.of(_tracks),
    );
  }

  Future<void> _loadSpace(int used) async {
    final device = AppScope.of(context).device;
    if (device == null || _loadingSpace) return;
    _loadingSpace = true;
    try {
      final root = await device.musicRoot();
      final free = await device.freeBytes(root.path);
      if (mounted) setState(() => _free = free + used);
    } on Object {
      // place inconnue : le curseur s'arrête à la limite (ou aux copies) ; la prochaine
      // construction de l'écran réessaie
    } finally {
      _loadingSpace = false;
    }
  }

  Future<void> _loadFolder() async {
    final app = AppScope.of(context);
    final device = app.device;
    if (device == null) return;
    String? name;
    try {
      if (app.settings?.musicFolder != null && await device.rootReachable()) {
        final parts = p.split((await device.musicRoot()).path);
        name = parts.skip(math.max(0, parts.length - 2)).join(' › ');
      }
    } on Object {
      name = null;
    }
    if (mounted) setState(() => _folder = name);
  }

  Future<void> _chooseFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _pickAndMove();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndMove() async {
    final app = AppScope.of(context);
    final device = app.device, downloader = app.downloader;
    if (device == null || downloader == null) return;
    final s = app.strings;
    final messenger = ScaffoldMessenger.of(context);
    final Directory old;
    final PickedFolder? picked;
    try {
      old = await device.musicRoot();
      picked = await device.pickFolder();
    } on FolderNotLocalException {
      say(messenger, s.folderNotLocal);
      return;
    } on FolderNotWritableException {
      say(messenger, s.folderNotWritable);
      return;
    } on Object {
      say(messenger, s.folderMoveFailed);
      return;
    }
    final c = picked;
    if (c == null) return;
    if (!mounted) {
      await _release(
        device,
      ); // l'écran est parti pendant le choix : le candidat est abandonné
      return;
    }
    // l'ancien dossier ne répond plus : rien à déplacer, on peut seulement adopter le nouveau
    var reachable = true;
    try {
      reachable = await device.rootReachable();
    } on Object {
      reachable = true; // moveRoot le redemandera
    }
    if (!reachable) {
      final choice = await _askAdopt(s);
      if (choice == _Missing.find) {
        await _release(device);
        if (mounted) await _relink(app, device, downloader, messenger);
        return;
      }
      if (choice != _Missing.adopt || !mounted) {
        await _release(device);
        return;
      }
    }
    setState(() => _moving = true);
    KeepResult? r;
    try {
      r = reachable
          ? await downloader.moveRoot(
              from: old,
              to: Directory(c.path),
              commit: () => device.commitFolder(c),
            )
          : await downloader.adoptRoot(commit: () => device.commitFolder(c));
    } on Object {
      r = null;
    }
    if (r != null && r.ok) {
      // un dossier adopté sans copie à déplacer ne prévient personne tout seul
      await app.accountService?.refreshRoot();
      unawaited(app.localFolder?.rescan());
      if (mounted) await _loadFolder();
    } else {
      await _release(
        device,
      ); // déjà fait par le téléchargeur ; sans effet la deuxième fois
      say(
        messenger,
        r != null && r.neededBytes > 0
            ? s.notEnoughSpace(s.size(r.neededBytes))
            : s.folderMoveFailed,
      );
    }
    if (mounted) setState(() => _moving = false);
  }

  /// « Utiliser ce dossier » : les copies de l'ancien passeront dans « À réessayer ».
  /// « Chercher l'ancien dossier » : on le retrouve au lieu d'en adopter un autre.
  Future<_Missing> _askAdopt(Strings s) async {
    final yes = await showDialog<_Missing>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: Text(
          s.oldFolderMissing,
          style: const TextStyle(
            color: LafleurColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          s.oldFolderMissingExplain,
          style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Missing.cancel),
            child: Text(
              s.cancel,
              style: const TextStyle(color: LafleurColors.text),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Missing.find),
            child: Text(
              s.findOldFolder,
              style: const TextStyle(color: LafleurColors.text),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Missing.adopt),
            child: Text(
              s.useThisFolder,
              style: const TextStyle(
                color: LafleurColors.pink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return yes ?? _Missing.cancel;
  }

  /// La copie est là à la bonne taille ; un fichier mis de côté par iCloud compte sans taille.
  bool _isKept(String root, OfflineRow o) {
    final abs = p.join(root, o.filePath!);
    final file = File(abs);
    if (file.existsSync()) return file.lengthSync() == o.size;
    return fileOrPlaceholderExists(abs);
  }

  /// L'utilisateur désigne l'ancien dossier : s'il contient toutes les copies finies
  /// (même taille), il redevient le dossier courant. Rien n'est déplacé, changé ni effacé.
  Future<void> _relink(
    AppScope app,
    Device device,
    Downloader downloader,
    ScaffoldMessengerState messenger,
  ) async {
    final s = app.strings;
    final PickedFolder? found;
    try {
      found = await device.pickFolder();
    } on FolderNotLocalException {
      say(messenger, s.folderNotLocal);
      return;
    } on FolderNotWritableException {
      say(messenger, s.folderNotWritable);
      return;
    } on Object {
      say(messenger, s.folderMoveFailed);
      return;
    }
    if (found == null) return;
    var has = false;
    try {
      final done = [
        for (final o in await app.db.offlineRows())
          if (o.state == OfflineState.done.name && o.filePath != null) o,
      ];
      // tous les fichiers gardés, à la bonne taille : un dossier qui n'en a que
      // quelques-uns (ou des homonymes) n'est pas l'ancien dossier
      has = done.isNotEmpty && done.every((o) => _isKept(found!.path, o));
    } on Object {
      await _release(device);
      say(messenger, s.folderMoveFailed);
      return;
    }
    if (!has || !mounted) {
      await _release(device);
      if (mounted) say(messenger, s.relinkNotFound);
      return;
    }
    setState(() => _moving = true);
    try {
      await device.commitFolder(found);
    } on Object {
      await _release(device);
      say(messenger, s.folderMoveFailed);
      if (mounted) setState(() => _moving = false);
      return;
    }
    downloader.start();
    await app.accountService?.refreshRoot();
    unawaited(app.localFolder?.rescan());
    if (mounted) await _loadFolder();
    say(messenger, s.relinked);
    if (mounted) setState(() => _moving = false);
  }

  Future<void> _release(Device device) async {
    try {
      await device.releaseCandidate();
    } on Object {
      // rien de plus à faire
    }
  }

  /// Par « Garder » : la limite, la place et le dossier sont vérifiés comme au premier essai.
  Future<void> _retry(_Failed f) async {
    final app = AppScope.of(context);
    final downloader = app.downloader;
    if (downloader == null) return;
    final messenger = ScaffoldMessenger.of(context);
    for (final e in f.byReason.entries) {
      final r = await downloader.keep([
        for (final p in e.value) ?_data.tracks[p],
      ], reason: e.key);
      if (!r.ok) {
        say(messenger, refusal(app.strings, r));
        return;
      }
    }
  }

  Future<void> _remove(_Kept k) async {
    await AppScope.of(context).downloader?.forget(k.paths, byUser: true);
  }

  Future<void> _removeSheet(_Kept k) async {
    final s = AppScope.of(context).strings;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
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
                child: Text(
                  k.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(ctx).pop(true),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      s.removeFromDevice(onIphone),
                      style: const TextStyle(fontSize: 16, color: _red),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (remove == true) await _remove(k);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final d = _data;
    final limit =
        app.settings?.storageLimitBytes ?? AppSettings.defaultStorageLimitBytes;
    final gauge = limit <= 0 ? 0.0 : (d.used / limit).clamp(0.0, 1.0);
    final limitGb = math.max(1, (limit / _gib).round());
    final free = _free;
    // la place libre n'abaisse jamais la limite réglée : elle ne fait que borner le curseur
    final knownGb = free == null
        ? (d.used + _gib - 1) ~/
              _gib // place inconnue : au moins les copies
        : free ~/ _gib;
    final shownGb = _dragGb ?? limitGb;
    final maxGb = math.max(math.max(1, knownGb), shownGb);
    if (free == null && !_loadingSpace && app.device != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _loadSpace(_data.used) : null,
      );
    }
    return PhoneScaffold(
      mini: false,
      header: PhoneHeader(back: s.home),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
        children: [
          if (d.queued.isNotEmpty) ...[
            PhoneSection(s.inProgress(d.queued.length - 1)),
            _current(d, s),
          ],
          if (d.kept.isNotEmpty) ...[
            PhoneSection(s.keptSection),
            for (final k in d.kept) _keptRow(k, s),
          ],
          if (d.failed.isNotEmpty) ...[
            PhoneSection(s.toRetry),
            for (final f in d.failed) _failedRow(f, s),
          ],
          if (d.kept.isNotEmpty || d.failed.isNotEmpty)
            _hint(s.removeHint(onIphone), top: 18),
          const SizedBox(height: 10),
          PhoneSection(s.spaceOnDevice(onIphone)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              s.usedOf(s.size(d.used), s.size(limit)),
              style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const Key('gauge'),
                value: gauge,
                minHeight: 8,
                color: LafleurColors.pink,
                backgroundColor: const Color(0xFF2A2A2A),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PhoneSection(s.limitSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              s.size(shownGb * _gib),
              key: const Key('limit'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: LafleurColors.pink,
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 0,
                pressedElevation: 0,
              ),
              overlayShape: SliderComponentShape.noOverlay,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              key: const Key('limitSlider'),
              min: 1,
              max: maxGb.toDouble(),
              divisions: maxGb > 1 ? maxGb - 1 : null,
              value: shownGb.toDouble(),
              onChanged: maxGb > 1
                  ? (v) => setState(() => _dragGb = v.round())
                  : null,
              onChangeEnd: (v) {
                final gb = v.round();
                app.settings?.storageLimitBytes = gb * _gib;
                app.saveSettings?.call();
                setState(() => _dragGb = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.size(_gib), style: _lt),
                Text(
                  '${s.allTheFreeSpace} · ${s.size(maxGb * _gib)}',
                  style: _lt,
                ),
              ],
            ),
          ),
          _hint(s.top100Hint),
          if (app.device != null) ...[
            const SizedBox(height: 10),
            PhoneSection(s.folderSection),
            _folderRow(s),
            _folderButton(s),
            _hint(s.folderHint(onIphone)),
          ],
        ],
      ),
    );
  }

  static const _lt = TextStyle(color: Color(0xFF999999), fontSize: 12);

  Widget _hint(String text, {double top = 10}) => Padding(
    padding: EdgeInsets.fromLTRB(4, top, 4, 0),
    child: Text(text, style: _lt.copyWith(height: 1.5)),
  );

  Widget _current(_Data d, Strings s) {
    final app = AppScope.of(context);
    final downloader = app.downloader;
    return ListenableBuilder(
      listenable: downloader ?? ValueNotifier(0),
      builder: (context, _) {
        final running = downloader?.current;
        final row = d.queued.firstWhere(
          (r) => r.trackPath == running,
          orElse: () => d.queued.first,
        );
        final t = d.tracks[row.trackPath]!;
        final active = running == row.trackPath;
        final total = t.size > 0 ? t.size : unknownTrackSize;
        final shown = active ? (downloader!.progress.clamp(0.0, 1.0)) : 0.0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LafleurColors.bar,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              CoverImage(trackPath: t.path, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.album} · ${active ? s.mbOf((total * shown).round(), total) : s.size(total)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _lt,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        key: const Key('downloadProgress'),
                        value: shown,
                        minHeight: 4,
                        color: LafleurColors.pink,
                        backgroundColor: const Color(0xFF333333),
                      ),
                    ),
                    if (downloader != null && downloader.accessDenied)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          s.storageDenied,
                          style: const TextStyle(color: _red, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: active ? s.pause : s.resume,
                child: GestureDetector(
                  key: Key(active ? 'pause' : 'resume'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      active ? downloader?.pause() : downloader?.resume(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 22,
                      color: const Color(0xFFBBBBBB),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _keptRow(_Kept k, Strings s) {
    final info = k.top100Only
        ? '${s.songCount(k.done)} · ${s.size(k.bytes)}'
        : '${s.minutes(k.durationMs ~/ 60000)} · ${s.size(k.bytes)}';
    return Dismissible(
      key: ValueKey('kept-${k.name}'),
      direction: DismissDirection.endToStart,
      // les lignes s'en vont avec la base : la ligne revient en place, puis disparaît
      confirmDismiss: (_) async {
        await _remove(k);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: LafleurColors.pink,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          s.removeFromDevice(onIphone),
          style: const TextStyle(
            color: LafleurColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onLongPress: () => _removeSheet(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                CoverImage(trackPath: k.coverPath, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          k.name.isEmpty ? s.unknownArtist : k.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (k.top100Only) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: LafleurColors.pink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.top100Tag,
                            style: const TextStyle(
                              color: LafleurColors.ink,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ] else if (k.full) ...[
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
                Text(
                  info,
                  maxLines: 1,
                  style: const TextStyle(color: _dim, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failedRow(_Failed f, Strings s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        CoverImage(trackPath: f.coverPath, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.name.isEmpty ? s.unknownArtist : f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _red,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(s.notFoundOnServer, style: _lt),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          key: Key('retry-${f.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _retry(f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: LafleurColors.pink),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              s.retry,
              style: const TextStyle(
                color: LafleurColors.pink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _folderRow(Strings s) => Material(
    color: LafleurColors.bar,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : _chooseFolder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _folder ?? s.defaultFolder(onIphone),
                key: const Key('folder'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: _dim),
          ],
        ),
      ),
    ),
  );

  Widget _folderButton(Strings s) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Opacity(
      opacity: _busy ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('chooseFolder'),
          borderRadius: BorderRadius.circular(22),
          onTap: _busy ? null : _chooseFolder,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF444444)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              _moving ? s.moving : s.chooseTheFolder,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    ),
  );
}
