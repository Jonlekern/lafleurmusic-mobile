// Preuve du son sur téléphone (plan 1, tâche 3) : mpv joue sur iPhone et Android, envoie nos en-têtes HTTP,
// survit à un refus du serveur et publie la session multimédia (écran verrouillé, notification).
//
//   flutter test integration_test/sound_proof_test.dart -d <téléphone>
//
// Avec --dart-define=HOLD_SECONDS=90, le dernier essai laisse la musique tourner en boucle : le temps de
// verrouiller l'écran et de regarder la pochette et les boutons (étape 3 de la tâche).
import 'dart:async';
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

/// Borné : sur l'émulateur API 34 la sonde peut ne jamais répondre ; une absence de réponse vaut null.
Future<Map<Object?, Object?>?> osSession() async {
  try {
    return await _session
        .invokeMapMethod(
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'debugNowPlayingInfo'
              : 'debugMediaSessionState',
        )
        .timeout(const Duration(seconds: 2));
  } on TimeoutException {
    return null;
  }
}

/// Toute attente sur mpv ou la session est bornée : un blocage devient un échec, pas un gel.
const _bound = Duration(seconds: 10);
const _testTimeout = Timeout(Duration(minutes: 2));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  // Un seul lecteur, jamais fermé : un seul propriétaire de la session multimédia par appli,
  // et fermer mpv pendant que la sortie audio bouge a déjà fait planter le Mac.
  final mpv = Player(configuration: const PlayerConfiguration(autoPlay: true));
  final bytes = base64Decode(aFlacBase64);
  late final String dir;
  late final HttpServer server;
  late final String base;
  final asked = <String?>[];

  /// Une copie de a.flac sous un nom à elle (écrites au début) : chaque essai a son propre
  /// morceau, pour qu'une position venue du morceau d'avant ne puisse pas compter.
  String localCopy(String name) => '$dir/$name.flac';

  /// Même idée sur le serveur, qui sert a.flac à n'importe quel chemin.
  String urlOf(String name) => '$base/$name.flac';

  setUpAll(() async {
    dir = (await getApplicationDocumentsDirectory()).path;
    for (final name in ['a', 'c', 'd']) {
      await File(localCopy(name)).writeAsBytes(bytes, flush: true);
    }

    // Un petit serveur à la Navidrome : il ne sert le morceau qu'avec le bon en-tête.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
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

    await mpv.setVolume(40).timeout(_bound);
    // a.flac n'a pas de pochette : on prend la fleur de l'appli pour voir l'image sur l'écran verrouillé
    final fleur = await rootBundle.load('assets/fleur.png');
    await mpv
        .setMediaSession(
          MediaSession(
            artwork: MediaSessionArtwork.custom(
              CoverArt(
                bytes: fleur.buffer.asUint8List(),
                mimeType: 'image/png',
              ),
            ),
          ),
        )
        .timeout(_bound);
  });

  /// Ouvre [media] et exige, en 5 s **en tout**, que **ce** morceau dépasse 1 s de lecture :
  /// on attend le « prêt » de mpv pour cette ouverture-ci, puis une position > 1 s
  /// relevée pendant que le morceau en cours de mpv est bien [media] (nom unique par essai).
  Future<void> playsPastOneSecond(WidgetTester tester, Media media) async {
    bool isCurrent() {
      final list = mpv.state.playlist;
      return list.index >= 0 &&
          list.index < list.items.length &&
          list.items[list.index].uri == media.uri;
    }

    await tester.runAsync(() async {
      final ready = mpv.stream.seekCompleted.first;
      await () async {
        await mpv.open(media).timeout(_bound);
        await ready;
        await mpv.stream.position.firstWhere(
          (d) => d > const Duration(seconds: 1) && isCurrent(),
        );
      }().timeout(const Duration(seconds: 5));
    });
    expect(isCurrent(), isTrue);
    expect(mpv.state.playing, isTrue);
  }

  testWidgets('(a) un fichier du dossier de l’appli joue', (tester) async {
    await playsPastOneSecond(tester, Media(localCopy('a')));
  }, timeout: _testTimeout);

  testWidgets('(b) un flux http joue avec l’en-tête demandé', (tester) async {
    asked.clear();
    await playsPastOneSecond(
      tester,
      Media(urlOf('b'), httpHeaders: {header: 'ok'}),
    );
    expect(asked, isNotEmpty);
    expect(asked, everyElement('ok'));
  }, timeout: _testTimeout);

  testWidgets('(c) sans l’en-tête : erreur signalée, l’appli tient', (
    tester,
  ) async {
    asked.clear();
    late MpvFileEndedEvent ended;
    await tester.runAsync(() async {
      final end = mpv.stream.endFile.firstWhere(
        (e) => e.reason != MpvEndFileReason.stop,
      );
      await mpv.open(Media(urlOf('c'))).timeout(_bound);
      ended = await end.timeout(const Duration(seconds: 10));
    });
    expect(asked, isNotEmpty);
    expect(asked, everyElement(isNull)); // le serveur a bien répondu 403
    expect(ended.reason, MpvEndFileReason.error);
    // l'appli tient : le même lecteur rejoue juste après
    await playsPastOneSecond(tester, Media(localCopy('c')));
  }, timeout: _testTimeout);

  testWidgets('(d) session multimédia publiée, (e) fréquence de sortie', (
    tester,
  ) async {
    await mpv.setLoop(Loop.file).timeout(_bound);
    // même si une vérification échoue, la boucle ne doit pas rester pour la suite
    addTearDown(
      () => tester.runAsync(() => mpv.setLoop(Loop.off).timeout(_bound)),
    );
    await playsPastOneSecond(tester, Media(localCopy('d')));
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
    await mpv.pause().timeout(_bound);
  }, timeout: _testTimeout);
}
