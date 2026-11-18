# Preuve du son sur téléphone (plan 1, tâche 3)

La question : le moteur de lecture du Mac (mpv, par `mpv_audio_kit` 0.5.1) marche-t-il aussi
sur iPhone et sur Android ? Si oui, on garde le même moteur partout. Si non, plan B sur ce
téléphone : `just_audio` + `audio_service`, sans égaliseur ni fondu au départ.

L'essai : `integration_test/sound_proof_test.dart`.

## iPhone (simulateur « iPhone LAFLEUR », iOS 27.2) — 18 novembre 2026

| Point | Réponse | Ce qu'on a vu |
| --- | --- | --- |
| (a) un fichier du téléphone joue | **OUI** | `a.flac` dépasse 1 s en moins de 5 s |
| (b) un flux `http://` joue avec notre en-tête | **OUI** | le petit serveur de l'essai reçoit `X-Lafleur-Test: ok` à chaque demande et le morceau joue |
| (c) sans l'en-tête : erreur, pas de plantage | **OUI** | le serveur répond 403, mpv signale une erreur de fin de fichier, puis le même lecteur rejoue aussitôt |
| (d) session multimédia publiée | **OUI** | le système affiche : titre « Ocean_Drive », artiste, album, pochette présente, état « lecture » (lu dans `MPNowPlayingInfoCenter`) |
| (e) fréquence de sortie | **notée** | le fichier est à 44,1 kHz, la sortie aussi à 44,1 kHz (16 bits, stéréo) : pas de sortie forcée à 48 kHz comme sur le Mac |
| musique qui continue en arrière-plan | **OUI, observé à la main, en debug** | `UIBackgroundModes` = `audio` ; l'appli mise en arrière-plan (Réglages ouverts) jouait encore après 65 s. Ce n'est pas un essai enregistré, et une appli en debug n'est pas forcément mise en pause par iOS comme une vraie : à confirmer avec l'écran verrouillé |
| écran verrouillé : pochette et boutons | **à regarder** | la machine ne peut pas verrouiller le simulateur sans l'accord de Johnny ; ce que le système doit afficher est déjà vérifié en (d) |

Décision iPhone : **on garde mpv** (l'essai Android est réussi, voir plus bas). Reste l'écran verrouillé, à regarder à la main.

## Android (émulateur API 34, Pixel 6, sur GitHub) — 18 novembre 2026

Essai GitHub n° 44315104790 (commit `5249640`), tâche `android-emulator` : tout réussi.

| Point | Réponse | Ce qu'on a vu |
| --- | --- | --- |
| (a) un fichier du téléphone joue | **OUI** | `a.flac` joue |
| (b) un flux `http://` joue avec notre en-tête | **OUI** | le petit serveur de l'essai reçoit l'en-tête et le morceau joue |
| (c) sans l'en-tête : erreur, pas de plantage | **OUI** | erreur signalée, le même lecteur rejoue ensuite |
| (d) session multimédia publiée | **OUI** | état « lecture », titre « Ocean_Drive », artiste « Johnny », album « Studio_Lafleur », pochette présente |
| (e) fréquence de sortie | **notée** | fichier à 44,1 kHz, sortie à 44,1 kHz (16 bits) |
| l'appli entière, de bout en bout | **OUI** | `app_test` : ajout du compte, albums, pochettes, et « Night Drive » joue (dépasse 1 s) |

Décision : **on garde mpv sur iPhone et sur Android.** Reste à regarder à la main l'écran verrouillé sur un vrai téléphone.

## Bon à savoir

- Le son de l'essai est `test/fixtures/a.flac`, embarqué dans `integration_test/fixture_bytes.dart`
  (un téléphone ne lit pas le dépôt). `test/fixture_bytes_test.dart` vérifie qu'ils sont identiques.
- Android : l'appli accepte le `http://` (`usesCleartextTraffic`), car un Navidrome maison n'a souvent pas de `https://`.
- Pour regarder l'écran verrouillé à la main :
  `flutter test integration_test/sound_proof_test.dart -d "iPhone LAFLEUR" --dart-define=HOLD_SECONDS=90`
  laisse la musique tourner 90 s.
