// Preuve du son sur téléphone (plan 1, tâche 3) : mpv joue sur iPhone et Android, envoie nos en-têtes HTTP,
// survit à un refus du serveur et publie la session multimédia (écran verrouillé, notification).
//
//   flutter test integration_test/sound_proof_test.dart -d <téléphone>
//
// Avec --dart-define=HOLD_SECONDS=90, le dernier essai laisse la musique tourner en boucle : le temps de
// verrouiller l'écran et de regarder la pochette et les boutons (étape 3 de la tâche).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/player/player.dart' show AudioInfo;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'fixture_bytes.dart';

const holdSeconds = int.fromEnvironment('HOLD_SECONDS');
const header = 'X-Lafleur-Test';

/// Titre écrit dans les tags de a.flac : c'est lui que l'écran verrouillé doit montrer.
const fileTitle = 'Ocean_Drive';

/// Sonde de test du paquet : ce que le système affiche vraiment
/// (MPNowPlayingInfoCenter sur iPhone, la session Media3 sur Android).
const _session = MethodChannel('mpv_audio_kit/media_session');
Future<Map<Object?, Object?>?> osSession() => _session.invokeMapMethod(
  defaultTargetPlatform == TargetPlatform.iOS
      ? 'debugNowPlayingInfo'
      : 'debugMediaSessionState',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  // Un seul lecteur, jamais fermé : un seul propriétaire de la session multimédia par appli,
  // et fermer mpv pendant que la sortie audio bouge a déjà fait planter le Mac.
  final mpv = Player(configuration: const PlayerConfiguration(autoPlay: true));
  final bytes = base64Decode(aFlacBase64);
  late final String localPath;
  late final HttpServer server;
  late final String url;
  final asked = <String?>[];

  setUpAll(() async {
    final dir = await getApplicationDocumentsDirectory();
    localPath = '${dir.path}/a.flac';
    await File(localPath).writeAsBytes(bytes, flush: true);

    // Un petit serveur à la Navidrome : il ne sert le morceau qu'avec le bon en-tête.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/a.flac';
    server.listen((req) async {
      final value = req.headers.value(header);
      asked.add(value);
      if (value != 'ok') {
        req.response.statusCode = HttpStatus.forbidden;
      } else {
        req.response.headers.contentType = ContentType('audio', 'flac');
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
      }
      await req.response.close();
    });

    await mpv.setVolume(40);
    // a.flac n'a pas de pochette : on prend la fleur de l'appli pour voir l'image sur l'écran verrouillé
    final fleur = await rootBundle.load('assets/fleur.png');
    await mpv.setMediaSession(
      MediaSession(
        artwork: MediaSessionArtwork.custom(
          CoverArt(bytes: fleur.buffer.asUint8List(), mimeType: 'image/png'),
        ),
      ),
    );
  });

  /// Ouvre [media] et attend que mpv dise « prêt », puis que la lecture dépasse 1 s (5 s au plus).
  Future<void> playsPastOneSecond(WidgetTester tester, Media media) async {
    await tester.runAsync(() async {
      final ready = mpv.stream.seekCompleted.first;
      await mpv.open(media);
      await ready.timeout(const Duration(seconds: 5));
      await mpv.stream.position
          .firstWhere((d) => d > const Duration(seconds: 1))
          .timeout(const Duration(seconds: 5));
    });
    expect(mpv.state.playing, isTrue);
  }

  testWidgets('(a) un fichier du dossier de l’appli joue', (tester) async {
    await playsPastOneSecond(tester, Media(localPath));
  });

  testWidgets('(b) un flux http joue avec l’en-tête demandé', (tester) async {
    asked.clear();
    await playsPastOneSecond(tester, Media(url, httpHeaders: {header: 'ok'}));
    expect(asked, isNotEmpty);
    expect(asked, everyElement('ok'));
  });

  testWidgets('(c) sans l’en-tête : erreur signalée, l’appli tient', (
    tester,
  ) async {
    asked.clear();
    late MpvFileEndedEvent ended;
    await tester.runAsync(() async {
      final end = mpv.stream.endFile.firstWhere(
        (e) => e.reason != MpvEndFileReason.stop,
      );
      await mpv.open(Media(url));
      ended = await end.timeout(const Duration(seconds: 10));
    });
    expect(asked, isNotEmpty);
    expect(asked, everyElement(isNull)); // le serveur a bien répondu 403
    expect(ended.reason, MpvEndFileReason.error);
    // l'appli tient : le même lecteur rejoue juste après
    await playsPastOneSecond(tester, Media(localPath));
  });

  testWidgets('(d) session multimédia publiée, (e) fréquence de sortie', (
    tester,
  ) async {
    await mpv.setLoop(Loop.file);
    await playsPastOneSecond(tester, Media(localPath));
    expect(mpv.state.mediaSession, isNotNull);

    // la publication vers le système suit le chargement du fichier : on la guette un instant
    Map<Object?, Object?>? os;
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        os = await osSession();
        if (os?['title'] == fileTitle &&
            os?['playbackState'] == 'playing' &&
            os?['hasArtwork'] == true) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    debugPrint('PREUVE session système : $os');
    expect(os?['title'], fileTitle);
    expect(os?['playbackState'], 'playing');
    expect(os?['hasArtwork'], isTrue);

    final decoded = mpv.state.audioParams;
    final out = mpv.state.audioOutParams;
    final info = AudioInfo(
      khz: decoded.sampleRate == null
          ? null
          : (decoded.sampleRate! / 1000).round(),
      channels: decoded.channelCount,
    );
    debugPrint(
      'PREUVE fréquence : AudioInfo.khz=${info.khz} '
      '(fichier ${decoded.sampleRate} Hz ${decoded.format?.name} '
      '${decoded.channelCount} canal) → sortie ${out.sampleRate} Hz '
      '${out.format?.name} ${out.channelCount} canaux',
    );
    expect(info.khz, 44);
    expect(out.sampleRate, isNotNull);

    if (holdSeconds > 0) {
      debugPrint('PREUVE : lecture en boucle pendant $holdSeconds s');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: holdSeconds)),
      );
      expect(mpv.state.playing, isTrue);
    }
    await mpv.setLoop(Loop.off);
    await mpv.pause();
  });
}
