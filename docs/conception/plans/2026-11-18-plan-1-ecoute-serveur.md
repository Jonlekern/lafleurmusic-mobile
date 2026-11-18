# LAFLEURMUSIC téléphone — plan 1 « écouter son serveur » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** une appli Android + iPhone qui se branche sur un serveur Subsonic (Navidrome), affiche la bibliothèque en colonnes empilées (écrans 1, 2, 3, 6, 7 des maquettes) et joue la musique en direct, écran éteint compris.

**Architecture:** copie de LAFLEURMUSIC ordi 1.0.1, sans les pièces propres à l'ordinateur. Un morceau garde une clé texte `path` ; pour un serveur c'est `subsonic://<accountId>/<songId>`. Un `MediaResolver` transforme cette clé en `Media` (URL + en-têtes) pour mpv, et `Covers` sait télécharger une pochette de serveur. Les écrans du Mac sont réutilisés, posés l'un après l'autre par un `PhoneShell`.

**Tech Stack:** Flutter 3.47.7, `mpv_audio_kit` 0.5.1, `drift`, `http` (+ `package:http/testing` `MockClient`), `crypto`, `flutter_secure_storage`, GitHub Actions (`reactivecircus/android-emulator-runner`).

**Spec:** `docs/conception/specs/2026-11-18-lafleurmusic-mobile-design.md` · Maquettes : `maquettes/1-telephone-debout.png`, `maquettes/2-coverflow-comptes.png`.

## Découpage du projet en plans

| Plan | Contenu | Spec |
|---|---|---|
| **1 (ce document)** | dépôt, GitHub, preuve du son, comptes Subsonic, synchro, lecture en direct, écrans 1-2-3-6-7, glisser = Lire ensuite, appui long (Lire ensuite / Ajouter à la file) | §3, 4.1, 4.2, 4.5 (debout), 4.6 |
| 2 « hors ligne » | Garder sur le téléphone (écran 8), dossier LAFLEURMUSIC visible, fichiers posés à la main, grisé dehors, écoutes en attente, Top 100 gardé tout seul, limite de place, « À la maison » | 4.4, 5, 8 |
| 3 « plusieurs comptes » | fusion Un / Tout / Perso, meilleure source, playlists du serveur, Cover Flow couché, tablette | 4.3, 4.5 |
| 4 « Jellyfin » | `jellyfin.dart` | 3 |
| 5 « Plex » | `plex.dart`, connexion par code plex.tv | 3 |
| 6 « molette » | **maquette d'abord, validée par Johnny**, puis le mode molette caché | 4.5 |

## Global Constraints

- Aucun visuel hors maquettes validées (`maquettes/1-telephone-debout.png`, `maquettes/2-coverflow-comptes.png`) sans nouvelle maquette validée par Johnny.
- Couleurs et police du Mac (`lib/theme/colors.dart` : fond `#0D0D0D`, barres `#1C1C1C`, rose `#F26EF2`, Inter) ; logo `assets/logo-texte-grand.png`.
- Android 7+ (SDK 24), iOS 15+ ; Flutter ≥ 3.47.4.
- Textes FR / EN dans `lib/l10n/strings.dart`, comme sur le Mac.
- Mots de passe, jetons et en-têtes : seulement dans `flutter_secure_storage`, jamais dans `settings.json`, jamais dans un journal.
- Les en-têtes HTTP d'un compte partent avec **toutes** ses requêtes : API, pochettes, flux mpv.
- Aucun code d'Amperfy (GPL-3). Licence MIT, logos LAFLEUR réservés.
- Commits en anglais, auteur `Jonlekern <288344322+Jonlekern@users.noreply.github.com>`, **sans** ligne Co-Authored-By ni mention d'IA.
- Dépôt GitHub `Jonlekern/lafleurmusic-mobile` **privé** ; chaque `git push` demandé à Johnny avant.
- Jamais la vraie bibliothèque ni le vrai Navidrome de Johnny dans les tests : fichiers `test/fixtures/` (sons générés) et faux serveur.
- Après chaque essai montré à Johnny : dire s'il faut redémarrer quelque chose.

## Review Focus

1. **Mot de passe avec caractères spéciaux** (`é`, `&`, `+`, espace) : le jeton Subsonic `md5(motdepasse + sel)` doit être calculé sur l'UTF-8 et l'URL bien encodée — test en tâche 4.
2. **Serveur derrière un proxy qui exige un en-tête** : sans l'en-tête, 401/403 ; l'appli doit dire « en-tête refusé par le proxy », pas « mauvais mot de passe » — test en tâche 4.
3. **Bibliothèque de plusieurs milliers d'albums** : la synchro doit aller par pages (500 albums) et ne pas tout charger en mémoire d'un coup — test en tâche 6 (1 200 albums simulés).
4. **Serveur coupé pendant la synchro** : la dernière liste connue reste, rien n'est effacé — test en tâche 6.
5. **Morceau qui disparaît du serveur** alors qu'il est dans la file : il est sauté, pas de plantage — test en tâche 7.

---

### Task 1: Le dépôt `lafleurmusic-mobile`, copie allégée de l'appli Mac

**Files:**
- Create: dossier `lafleurmusic-mobile/` (à côté de `lafleurmusic-desktop/`, qui contient déjà `docs/` et `maquettes/`) ; `android/`, `ios/` par `flutter create`
- Copy from desktop: `lib/`, `test/`, `assets/`, `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `tool/`, `integration_test/`
- Delete: `lib/skins/`, `lib/ui/winamp/`, `lib/ui/window_mode.dart`, `lib/repair/`, `lib/ui/repair_dialog.dart`, `lib/platform/trash.dart`, `lib/library/track_ops.dart`, `lib/ui/track_edit_dialog.dart`, `lib/ui/delete_dialog.dart`, `lib/ui/cover_drop.dart`, `lib/ui/artist_photo_drop.dart`, `lib/artists/`, `lib/app_exit.dart`, `lib/library/folders.dart`, `lib/ui/welcome_screen.dart`, `lib/library/repair_rules.dart`, `lib/library/playlist_ops.dart`, et leurs tests
- Modify: `pubspec.yaml` (retirer `window_manager`, `desktop_drop`, `file_selector`, `archive`, `url_launcher` ; ajouter `flutter_secure_storage` ; `name: lafleurmusic`, `version: 0.1.0+1`, `description: "LAFLEURMUSIC for phones: an iPod-style player for your music server."`), `lib/main.dart`, `lib/app_scope.dart` (retirer les champs des pièces supprimées), `lib/ui/track_menu.dart` (garder Lire ensuite / Ajouter à la file), `lib/ui/library_screen.dart`, `lib/ui/sidebar.dart` (retirer « À réparer », Genres reste)
- Create: `README.md` (anglais), `.gitignore` de Flutter

**Interfaces:**
- Produces: `lib/library/scanner.dart` est gardé (il resservira au plan 2 pour le dossier LAFLEURMUSIC du téléphone) ; un projet qui compile pour Android et iOS et dont `flutter test` passe ; `AppScope` sans `writer`, `musicbrainz`, `artists`, `skins`, `window`, `ops`, `pickAudio`.

- [ ] **Step 1:** `flutter create --platforms=android,ios --org studio.lafleur --project-name lafleurmusic .` dans `lafleurmusic-mobile/`, puis copier les fichiers du Mac listés ci-dessus.
- [ ] **Step 2:** supprimer les fichiers listés et ce qui les appelle ; `flutter analyze` → `No issues found!`
- [ ] **Step 3:** `flutter test` → tous les tests restants passent (les goldens du Mac en 1440×900 restent valides : on ne change pas encore les écrans).
- [ ] **Step 4:** `flutter build apk --debug` est fait par GitHub (tâche 2) ; ici : `flutter build ios --simulator --debug --no-codesign` → `Built build/ios/iphonesimulator/Runner.app`.
- [ ] **Step 5:** README anglais (ce que c'est, serveurs pris en charge, « Build from source », licence MIT + logos réservés), sans mention d'IA.
- [ ] **Step 6:** `git init -b main`, `git config user.name Jonlekern`, `git config user.email 288344322+Jonlekern@users.noreply.github.com`, commit `chore: start LAFLEURMUSIC for phones from the desktop app 1.0.1`.

### Task 2: GitHub Actions — tests et APK

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: à chaque push, un job `test` (ubuntu, `flutter test`) et un job `android` (ubuntu, `flutter build apk --release`, artefact `LAFLEURMUSIC-android.apk`). Le job `android-emulator` est ajouté en tâche 3.

- [ ] **Step 1:** écrire `ci.yml` : `subosito/flutter-action@v2` avec `flutter-version: 3.47.7`, `actions/setup-java@v4` Java 17, cache pub ; `flutter pub get` ; `dart run build_runner build --delete-conflicting-outputs` ; `flutter test` ; `flutter build apk --release` (signature debug pour l'instant) ; `actions/upload-artifact@v4`.
- [ ] **Step 2:** demander à Johnny : « Je crée le dépôt privé `Jonlekern/lafleurmusic-mobile` et j'envoie le code ? » — attendre son oui.
- [ ] **Step 3:** `gh repo create Jonlekern/lafleurmusic-mobile --private --source . --push`.
- [ ] **Step 4:** `gh run watch` → les deux jobs verts ; `gh run download` → l'APK existe (> 20 Mo).
- [ ] **Step 5:** commit `ci: run tests and build the Android APK on GitHub`.

### Task 3: Preuve du son sur iPhone et Android (go / plan B)

**Files:**
- Create: `integration_test/sound_proof_test.dart`, `test/fixtures/tone.flac` (déjà dans les fixtures du Mac : `a.flac`)
- Modify: `ios/Runner/Info.plist` (`UIBackgroundModes` = `audio`), `android/app/src/main/AndroidManifest.xml` (permissions `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, `WAKE_LOCK` ; `android:usesCleartextTraffic="true"` car Navidrome maison est en `http://`), `.github/workflows/ci.yml` (job `android-emulator`, API 34, x86_64)

**Interfaces:**
- Produces: une réponse écrite dans `docs/conception/plans/preuve-son.md` : OUI / NON pour chaque point, sur chaque téléphone.

- [ ] **Prérequis (Johnny) :** le Mac n'a **aucun simulateur iPhone**. Demander à Johnny son accord pour télécharger le simulateur iOS d'Apple (gratuit, ~8 Go) : `xcodebuild -downloadPlatform iOS`, puis `xcrun simctl create "iPhone LAFLEUR" "iPhone 17"`.
- [ ] **Step 1: test d'intégration** `sound_proof_test.dart` : (a) joue `a.flac` copié dans le dossier de l'appli → `position` dépasse 1 s en moins de 5 s ; (b) démarre dans le test un `HttpServer` sur `127.0.0.1` qui sert `a.flac` **seulement** si l'en-tête `X-Lafleur-Test: ok` est présent (sinon 403) → mpv joue avec `Media(url, httpHeaders: {'X-Lafleur-Test': 'ok'})` et `position` > 1 s ; (c) sans l'en-tête → mpv signale une erreur, l'appli ne plante pas ; (d) la session multimédia est publiée (titre visible dans `MediaSession` de mpv_audio_kit) ; (e) noter la fréquence de sortie (`AudioInfo.khz`).
- [ ] **Step 2:** `flutter test integration_test/sound_proof_test.dart -d "iPhone LAFLEUR"` → PASS ; pousser (accord de Johnny) → job `android-emulator` PASS.
- [ ] **Step 3: à l'oreille et à l'œil, sur le simulateur iPhone :** lancer l'appli, jouer, verrouiller l'écran → la musique continue, la pochette et les boutons sont sur l'écran verrouillé. Capture envoyée à Johnny.
- [ ] **Step 4: décision.** Tout OUI → on continue. Un NON → **s'arrêter**, l'écrire dans `preuve-son.md` et le dire à Johnny : plan B `just_audio` + `audio_service` sur ce téléphone, sans égaliseur ni fondu au départ (spec §8). Ne pas continuer sans sa réponse.
- [ ] **Step 5:** commit `test: prove mpv playback, headers and background audio on iOS and Android`.

### Task 4: Client Subsonic

**Files:**
- Create: `lib/sources/source.dart`, `lib/sources/subsonic.dart`, `test/sources/subsonic_test.dart`, `test/fixtures/subsonic/*.json` (réponses enregistrées : `ping`, `getAlbumList2`, `getAlbum`, `getPlaylists`, erreur 40 « Wrong username or password »)

**Interfaces:**
- Produces:
```dart
class SourceAlbum { final String id, name, artist; final String? coverId; final int songCount; }
class SourceSong { final String id, title, artist, album, albumArtist, genre; final int? track, disc;
  final int durationMs, size; final String? coverId, suffix; final double? replayGainTrack, replayGainAlbum; final int playCount; }
enum TestResult { ok, unreachable, wrongPassword, headerRefused, notSubsonic }
abstract interface class MusicSource {
  String get accountId;
  Future<TestResult> test();
  Stream<List<SourceAlbum>> albums({int pageSize = 500});   // une page à la fois
  Future<List<SourceSong>> albumSongs(String albumId);
  Uri streamUri(String songId);                              // URL complète, authentifiée
  Uri coverUri(String coverId, int size);
  Map<String, String> get headers;                          // en-têtes du compte
  Future<void> scrobble(String songId, DateTime at);
}
class SubsonicSource implements MusicSource {
  SubsonicSource({required String accountId, required Uri base, required String user,
    required String password, Map<String, String> headers = const {}, http.Client? client, String Function()? salt});
}
```
- Paramètres de chaque requête : `u`, `t` = hex(md5(utf8(password + salt))), `s` = sel, `v=1.16.1`, `c=LAFLEURMUSIC`, `f=json`.

- [ ] **Step 1: tests** (`MockClient` qui vérifie chaque requête) :
  - `test() → ok` sur `ping` réussi ; `wrongPassword` sur `{"subsonic-response":{"status":"failed","error":{"code":40}}}` ; `unreachable` sur `SocketException` ; `headerRefused` sur HTTP 401/403 **sans** corps Subsonic ; `notSubsonic` sur HTML 200.
  - jeton : avec `password: 'é&+ x'` et `salt: () => 'abc'`, `t == md5Hex(utf8.encode('é&+ xabc'))` et l'URL contient `t=` encodé correctement.
  - en-têtes : `headers: {'CF-Access-Client-Id': 'id1'}` → **chaque** requête du test (ping, getAlbumList2, getAlbum, getCoverArt) porte `CF-Access-Client-Id: id1`.
  - `albums(pageSize: 500)` sur 1 200 albums simulés → 3 pages (500, 500, 200), requêtes `offset=0,500,1000`, type `alphabeticalByName`.
  - `albumSongs` lit `replayGain.trackGain` (OpenSubsonic) quand il existe, sinon `null`.
  - `scrobble` → `scrobble.view?id=…&time=<ms>&submission=true`.
- [ ] **Step 2:** `flutter test test/sources/subsonic_test.dart` → FAIL (classes absentes).
- [ ] **Step 3:** implémenter `source.dart` et `subsonic.dart` avec `package:http`.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** commit `feat: Subsonic client with token auth and custom headers`.

### Task 5: Comptes

**Files:**
- Create: `lib/sources/accounts.dart`, `lib/sources/secret_store.dart`, `test/sources/accounts_test.dart`
- Modify: `lib/library/db.dart` (table `Accounts`)

**Interfaces:**
- Consumes: `SubsonicSource` (tâche 4).
- Produces:
```dart
enum AccountType { subsonic, jellyfin, plex }
class Account { final String id; final AccountType type; final String name; final Uri base; final String user; final int order; }
abstract interface class SecretStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }
class SecureSecretStore implements SecretStore { /* flutter_secure_storage */ }
class Accounts {
  Accounts(LibraryDb db, SecretStore secrets);
  Stream<List<Account>> watch();
  Future<Account> add({required AccountType type, required String name, required Uri base, required String user,
                       required String password, Map<String, String> headers = const {}});
  Future<void> update(Account a, {String? password, Map<String, String>? headers});
  Future<void> remove(String id);          // efface aussi ses secrets et ses morceaux
  Future<void> reorder(List<String> ids);
  Future<MusicSource> source(String id);   // construit le SubsonicSource avec mot de passe + en-têtes
}
```
- Clés secrètes : `account.<id>.password`, `account.<id>.headers` (JSON).

- [ ] **Step 1: tests** (base drift en mémoire, `FakeSecretStore` = Map) : `add` → mot de passe et en-têtes dans le store, **absents** de la base (lecture brute de la table) ; `remove` → secrets effacés ; `reorder(['b','a'])` → `watch()` rend b puis a ; `source(id)` → `headers` égaux à ceux enregistrés.
- [ ] **Step 2:** → FAIL. **Step 3:** implémenter (migration de schéma : nouvelle base, `schemaVersion = 1` du téléphone ; pas de migration depuis le Mac). **Step 4:** → PASS.
- [ ] **Step 5:** commit `feat: accounts with passwords and headers in secure storage`.

### Task 6: Synchronisation serveur → base

**Files:**
- Create: `lib/library/sync.dart`, `test/library/sync_test.dart`
- Modify: `lib/library/db.dart` (`Tracks` : `accountId` texte, `remoteId` texte, `albumArtist`, `disc`, `coverId`, `suffix`, `replayGain` réel nullable ; `folderId` retiré ; `mtime` retiré ; `path` = `subsonic://<accountId>/<songId>`), `lib/library/models.dart` (mêmes champs sur `Track`)

**Interfaces:**
- Consumes: `MusicSource` (4), `Accounts` (5).
- Produces:
```dart
String trackKey(String accountId, String songId) => 'subsonic://$accountId/$songId';
class SyncResult { final int added, updated, removed; final bool complete; }
class LibrarySync { LibrarySync(LibraryDb db); Future<SyncResult> run(MusicSource s); }
```
- `PlayCounts` : au premier passage, `count = max(local, playCount du serveur)`.

- [ ] **Step 1: tests** avec une `FakeSource` :
  - première synchro de 3 albums / 20 morceaux → 20 lignes, clés `subsonic://acc1/<id>`.
  - deuxième synchro où 1 morceau a disparu et 1 a changé de titre → `removed: 1`, `updated: 1`.
  - **serveur coupé** à la 2ᵉ page (`albums()` lève `SocketException`) → `complete: false`, **aucune** ligne supprimée.
  - 1 200 albums → au plus 500 albums en mémoire à la fois (la `FakeSource` compte les pages non consommées).
  - `playCount: 12` côté serveur, 3 en local → `PlayCounts.count == 12`.
- [ ] **Step 2:** → FAIL. **Step 3:** implémenter (suppression seulement si `complete`). **Step 4:** → PASS ; les tests de `db_test.dart` adaptés aux nouvelles colonnes passent.
- [ ] **Step 5:** commit `feat: sync a Subsonic library into the local database`.

### Task 7: Lecture en direct et pochettes du serveur

**Files:**
- Create: `lib/player/media_resolver.dart`, `test/player/media_resolver_test.dart`
- Modify: `lib/player/mpv_port.dart` (`PlayerPort` reçoit un `MediaResolver` ; `Media(p)` → `resolver.media(p)`), `lib/player/crossfade.dart` (idem), `lib/library/covers.dart` (`Covers` reçoit `Future<Uint8List?> Function(String trackPath, int size) remote` pour les clés `subsonic://`), `lib/player/player.dart` (scrobble), `lib/library/play_counter.dart`

**Interfaces:**
- Consumes: `Accounts.source` (5), `trackKey` (6).
- Produces:
```dart
class MediaResolver {
  MediaResolver(Future<MusicSource> Function(String accountId) sourceOf);
  Future<Media> media(String path);           // fichier local → Media(path) ; subsonic:// → Media(streamUri, httpHeaders: headers)
}
Future<Uint8List?> remoteCover(MusicSource s, String coverId, int size); // GET coverUri avec headers
```
- `LafleurPlayer({MediaResolver? resolver})` ; `PlayerController` inchangé.
- Écoute comptée (règle du Mac « moitié ou 4 min ») → `MusicSource.scrobble(songId, at)` ; un échec réseau est ignoré ici (la file d'attente des écoutes est au plan 2).
- Écran verrouillé : la pochette est passée **en octets** à la session multimédia (pas d'URL : la session ne sait pas envoyer d'en-têtes).

- [ ] **Step 1: tests** : `media('subsonic://acc1/s9')` → URL `…/rest/stream.view?id=s9&u=…&t=…` et `httpHeaders == {'CF-Access-Client-Id': 'id1'}` ; `media('/x/a.flac')` → `Media('/x/a.flac')` sans en-têtes ; `Covers.get('subsonic://acc1/s9', 300)` → un seul téléchargement pour deux appels (mémoire) et fichier en cache ; **morceau disparu du serveur** (stream 404) dans une file de 3 → `skipped` émet son titre et le lecteur passe au 3ᵉ (faux port qui simule l'erreur, comme `test/player/skip_guard_test.dart`) ; `PlayCounter` à 50 % → `scrobble` appelé une fois.
- [ ] **Step 2:** → FAIL. **Step 3:** implémenter. **Step 4:** → PASS ; tous les tests `test/player/` passent.
- [ ] **Step 5:** commit `feat: stream from the server with headers, remote covers, scrobbles`.

### Task 8: Écrans téléphone debout (maquette 1 : écrans 1, 2, 3)

**Files:**
- Create: `lib/ui/phone/phone_shell.dart`, `lib/ui/phone/home_screen.dart`, `lib/ui/phone/album_screen.dart`, `lib/ui/phone/now_screen.dart`, `lib/ui/phone/mini_player.dart`, `test/ui/phone_golden_test.dart`, `test/ui/phone_widget_test.dart`, `test/ui/goldens/phone-1.png`, `phone-2.png`, `phone-3.png`
- Modify: `lib/main.dart` (largeur < 900 → `PhoneShell`, sinon la vue colonnes du Mac), `lib/ui/track_list.dart` (glisser vers la gauche = `playNext`, appui long = menu en feuille du bas), `lib/ui/track_menu.dart`, `lib/l10n/strings.dart`

**Interfaces:**
- Consumes: `PlayerController` (inchangé), flux de `LibraryDb` (`watchAlbums`, `watchAlbumTracks`, `watchTop`…), widgets du Mac (`TrackList`, `NowPanel`, `EqualizerPanel`, `PlaybackCard`, `CoverImage`).
- Produces: `PhoneShell` (navigateur : Accueil → Album/Artiste/Genre/Morceaux/Top 100 → En cours), `MiniPlayer` (en bas de l'Accueil et des listes ; toucher = En cours).

- [ ] **Step 1: tests** : goldens 390×844 des écrans 1, 2, 3 avec les données des maquettes (Studio Lafleur, Lafleur Surf, Summer Mix…), comparés à la maquette par Johnny (même méthode que le Mac : golden généré, montré à côté de la maquette) ; widget : toucher « Studio Lafleur » → écran Album ; toucher une ligne → `playTracks(album, i)` ; glisser « Night Swim » vers la gauche → `playNext([Night Swim])` et bandeau rose « Lire ensuite » ; appui long → feuille avec « Lire ensuite », « Ajouter à la file » ; toucher le mini-lecteur → En cours ; onglets À suivre / Égaliseur / Lecture ; glisser depuis le bord gauche = retour.
- [ ] **Step 2:** → FAIL. **Step 3:** implémenter en réutilisant les widgets du Mac. Les lignes « Garder sur mon iPhone » et « Sélectionner… » de l'écran 4 n'apparaissent pas encore (plan 2). **Step 4:** → PASS.
- [ ] **Step 5:** captures du simulateur iPhone des 3 écrans **montrées à Johnny** à côté de la maquette ; attendre son oui.
- [ ] **Step 6:** commit `feat: phone layout with stacked desktop columns`.

### Task 9: Comptes à l'écran (maquette 2 : écrans 6 et 7) et premier lancement

**Files:**
- Create: `lib/ui/phone/accounts_screen.dart`, `lib/ui/phone/account_form.dart`, `test/ui/accounts_widget_test.dart`, `test/ui/goldens/phone-6.png`, `phone-7.png`
- Modify: `lib/main.dart` (aucun compte → écran 7 au lancement ; synchro au lancement et en tirant la liste vers le bas), `lib/ui/phone/home_screen.dart` (⚙︎ → Réglages → Comptes ; étiquette « Hors ligne » si le serveur ne répond pas)

**Interfaces:**
- Consumes: `Accounts` (5), `SubsonicSource.test` (4), `LibrarySync.run` (6).

- [ ] **Step 1: tests** : formulaire → « Tester » affiche le bon message pour chaque `TestResult` (textes FR : « Ça marche ! », « Serveur injoignable », « Mauvais nom ou mot de passe », « En-tête refusé par le proxy », « Ce n'est pas un serveur Subsonic ») ; « + Ajouter un en-tête » ajoute une paire, ✕ la retire ; « Enregistrer » → `Accounts.add` puis `LibrarySync.run` ; Jellyfin et Plex visibles mais grisés « bientôt » ; écran 6 : glisser ⋮⋮ → `reorder` ; le choix d'affichage Un / Tout / Perso est visible mais seul « Un compte » est actif (plan 3) ; goldens 390×844 des écrans 6 et 7.
- [ ] **Step 2:** → FAIL. **Step 3:** implémenter. **Step 4:** → PASS.
- [ ] **Step 5:** commit `feat: account screens and first launch`.

### Task 10: Essai de bout en bout

**Files:**
- Create: `integration_test/fake_subsonic.dart` (faux serveur Subsonic en Dart, `HttpServer`, sert les réponses de `test/fixtures/subsonic/` et les fichiers `test/fixtures/a.*`, exige l'en-tête `X-Lafleur-Test`), `integration_test/app_test.dart`, `tool/navidrome-ci.sh`
- Modify: `.github/workflows/ci.yml` (job `navidrome` : service Docker `deluan/navidrome:latest`, dossier musique = `test/fixtures/`, compte créé par l'API, puis `flutter test test/sources/navidrome_contract_test.dart` contre lui)
- Create: `test/sources/navidrome_contract_test.dart` (ignoré si la variable `NAVIDROME_URL` est absente)

- [ ] **Step 1:** `app_test.dart` : lancer l'appli sans compte → écran 7 ; remplir l'adresse du faux serveur, utilisateur, mot de passe, en-tête `X-Lafleur-Test: ok` ; Tester → « Ça marche ! » ; Enregistrer → l'album apparaît à l'Accueil ; l'ouvrir, toucher le 1ᵉʳ morceau → `position` > 1 s en moins de 10 s.
- [ ] **Step 2:** simulateur iPhone : `flutter test integration_test/app_test.dart -d "iPhone LAFLEUR"` → PASS.
- [ ] **Step 3:** demander à Johnny d'envoyer sur GitHub → jobs `test`, `android`, `android-emulator` (avec `app_test.dart`), `navidrome` verts.
- [ ] **Step 4:** envoyer à Johnny l'APK et les captures du simulateur ; lui dire qu'il peut essayer sur son téléphone avec son vrai Navidrome à la maison (ses identifiants, tapés par lui), et s'il faut redémarrer quelque chose.
- [ ] **Step 5:** commit `test: end-to-end run against a fake Subsonic server and Navidrome in CI`.
