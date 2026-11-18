import 'dart:io';

import 'package:image/image.dart' as img;

import '../library/models.dart';

/// Bibliothèque inventée des maquettes (Studio Lafleur, Lafleur Surf, Summer Mix…) :
/// images de référence des tests et mode démo (debug seulement), sans serveur ni son.
abstract final class DemoLibrary {
  static Track _t(
    String album,
    int no,
    String title,
    String artist,
    int seconds,
  ) => Track(
    path: 'demo://$album/$no',
    folderId: 1,
    title: title,
    artist: artist,
    album: album,
    trackNo: no,
    durationMs: seconds * 1000,
    hasCover: true,
    mtime: 1,
    size: 1,
  );

  /// Studio Lafleur : 9 morceaux, 36 min.
  static final studio = [
    _t('Studio Lafleur', 1, 'Ocean Drive', 'Johnny', 222),
    _t('Studio Lafleur', 2, 'Lafleur Surf', 'LAFLEURSTUDIO', 245),
    _t('Studio Lafleur', 3, 'Golden Hour', 'Divers', 198),
    _t('Studio Lafleur', 4, 'Night Swim', 'Kavinsky', 301),
    _t('Studio Lafleur', 5, 'Paradise Club', 'Divers', 235),
    _t('Studio Lafleur', 6, 'Sunset Tape', 'Divers', 252),
    _t('Studio Lafleur', 7, 'Palm Waves', 'Johnny', 242),
    _t('Studio Lafleur', 8, 'Late Bloom', 'Divers', 238),
    _t('Studio Lafleur', 9, 'Studio 9', 'LAFLEURSTUDIO', 250),
  ];
  static final surf = [
    _t('Lafleur Surf', 1, 'Lafleur Surf', 'LAFLEURSTUDIO', 245),
    _t('Lafleur Surf', 2, 'Surf Radio', 'LAFLEURSTUDIO', 214),
  ];
  static final summer = [
    _t('Summer Mix', 1, 'Palm Springs', 'Divers', 231),
    _t('Summer Mix', 2, 'Heatwave', 'Johnny', 207),
  ];

  /// Ajouté à la file par l'utilisateur (hors bibliothèque).
  static final nightcall = _t('Night Drive', 1, 'Nightcall', 'Kavinsky', 258);

  static List<Track> get tracks => [...studio, ...surf, ...summer];

  static const _mib = 1024 * 1024;

  static Track _r(
    String album,
    int no,
    String title,
    String artist,
    int seconds,
    int bytes,
  ) => Track(
    path: 'subsonic://demo/$album/$no',
    folderId: 0,
    accountId: 'demo',
    remoteId: '$album/$no',
    title: title,
    artist: artist,
    album: album,
    trackNo: no,
    durationMs: seconds * 1000,
    hasCover: true,
    mtime: 1,
    size: bytes,
  );

  static List<Track> _remoteAlbum(
    String album,
    int minutes,
    int mib,
    List<(String, String)> songs,
  ) => [
    for (final (i, (title, artist)) in songs.indexed)
      _r(
        album,
        i + 1,
        title,
        artist,
        minutes * 60 ~/ songs.length,
        mib * _mib ~/ songs.length,
      ),
  ];

  /// La bibliothèque d'un serveur pour l'écran « Garder sur mon iPhone » (maquette 2, écran 8) :
  /// Studio Lafleur 36 min · 310 Mo, Summer Mix 52 min · 480 Mo, Night Drive 41 min · 390 Mo,
  /// Ports 28 min · 260 Mo ; Lafleur Surf est déjà gardé ([keptPaths]).
  static final remote = [
    for (final t in studio) // les vrais titres et durées : 36 min
      _r(
        'Studio Lafleur',
        t.trackNo!,
        t.title,
        t.artist,
        t.durationMs ~/ 1000,
        310 * _mib ~/ studio.length,
      ),
    ..._remoteAlbum('Lafleur Surf', 8, 190, [
      ('Lafleur Surf', 'LAFLEURSTUDIO'),
      ('Surf Radio', 'LAFLEURSTUDIO'),
    ]),
    ..._remoteAlbum('Summer Mix', 52, 480, [
      ('Palm Springs', 'Divers'),
      ('Heatwave', 'Johnny'),
      ('Sunburn', 'Divers'),
      ('Last Light', 'Divers'),
    ]),
    ..._remoteAlbum('Night Drive', 41, 390, [
      ('Nightcall', 'Kavinsky'),
      ('Rampage', 'Kavinsky'),
      ('Odd Look', 'Kavinsky'),
    ]),
    ..._remoteAlbum('Ports', 28, 260, [
      ('Harbour', 'Divers'),
      ('Ferry', 'Divers'),
    ]),
  ];

  /// « Golden Hour » de Summer Mix (19,6 Mo) : le téléchargement en cours de « Sur mon iPhone ».
  static final goldenHour = _r(
    'Summer Mix',
    5,
    'Golden Hour',
    'Divers',
    198,
    20552090,
  );

  /// Lafleur Surf pour « Sur mon iPhone » : 48 min (la maquette 4), mêmes chemins que [remote].
  static final surf48 = [
    for (final t in remote)
      if (t.album == 'Lafleur Surf')
        _r(t.album, t.trackNo!, t.title, t.artist, 24 * 60, t.size),
  ];

  /// Le 4e titre de Night Drive (« 4 titres · 38 Mo » de la maquette 4).
  static final nightDrive4 = _r(
    'Night Drive',
    4,
    'A Real Hero',
    'College',
    270,
    10 * _mib,
  );

  /// Les morceaux de Lafleur Surf : copiés sur le téléphone.
  static List<String> get keptPaths => [
    for (final t in remote)
      if (t.album == 'Lafleur Surf') t.path,
  ];

  /// Pas sur le téléphone et le serveur est injoignable : grisés (« Night Swim · Kavinsky »).
  static List<String> get notOnPhonePaths => [
    for (final t in remote)
      if (t.album == 'Studio Lafleur' && t.artist == 'Kavinsky') t.path,
  ];

  /// Pochette de chaque morceau de [remote] (la couleur de son album).
  static Map<String, img.Image> remoteCoverImages() {
    final studioCover = _studioCover();
    final colors = {
      'Lafleur Surf': _surfCover(),
      'Summer Mix': _solid(224, 181, 58),
      'Night Drive': _solid(44, 59, 120),
      'Ports': _solid(68, 68, 68),
    };
    return {
      for (final t in [...remote, goldenHour])
        t.path: colors[t.album] ?? studioCover,
    };
  }

  /// Lafleur Surf en cours (1:33 sur 4:05).
  static Track get playing => studio[1];
  static const position = Duration(seconds: 93);

  static img.Image _solid(int r, int g, int b) =>
      img.Image(width: 300, height: 300)..clear(img.ColorRgb8(r, g, b));

  static img.Image _studioCover() {
    final im = _solid(237, 232, 222);
    return img.fillRect(
      im,
      x1: 30,
      y1: 90,
      x2: 270,
      y2: 210,
      color: img.ColorRgb8(91, 138, 94),
    );
  }

  // ovale rouge cerclé de crème sur fond crème (pochette de « Lafleur Surf »)
  static img.Image _surfCover() {
    final im = _solid(237, 232, 222);
    const cx = 150.0, cy = 150.0;
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 300; x++) {
        final dx = (x - cx) / 100, dy = (y - cy) / 55;
        final d = dx * dx + dy * dy;
        if (d <= 1) {
          im.setPixelRgb(x, y, 158, 44, 54);
        } else if (d <= 1.12) {
          im.setPixelRgb(x, y, 240, 217, 160);
        }
      }
    }
    return im;
  }

  /// Une image de pochette par morceau.
  static Map<String, img.Image> coverImages() {
    final studioCover = _studioCover();
    final surfCover = _surfCover();
    final red = _solid(143, 31, 42);
    final yellow = _solid(224, 181, 58);
    return {
      for (final t in studio) t.path: studioCover,
      playing.path: surfCover,
      for (final t in surf) t.path: red,
      for (final t in summer) t.path: yellow,
      nightcall.path: _solid(44, 59, 120),
    };
  }

  /// Écrit les pochettes en JPEG dans [dir] : chemin du morceau → fichier.
  static Map<String, File> writeCovers(
    Directory dir, {
    Map<String, img.Image>? images,
  }) {
    final files = Map<img.Image, File>.identity();
    var n = 0;
    return {
      for (final e in (images ?? coverImages()).entries)
        e.key: files.putIfAbsent(
          e.value,
          () =>
              File('${dir.path}/demo-${n++}.jpg')
                ..writeAsBytesSync(img.encodeJpg(e.value)),
        ),
    };
  }
}
