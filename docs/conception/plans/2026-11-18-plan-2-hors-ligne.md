# LAFLEURMUSIC téléphone — plan 2 « hors ligne » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** « Garder sur mon iPhone / téléphone » : des morceaux du serveur deviennent de vrais fichiers dans un dossier visible et jouent sans réseau ; dehors, le reste est grisé ; les écoutes faites dehors partent au serveur au retour ; le Top 100 se garde tout seul à la maison, dans une limite de place.

**Architecture:** un nouveau dossier `lib/offline/` (file de téléchargements, place, limite, écoutes en attente, « à la maison »). La base passe en version 2 (tables `Offline` et `PendingScrobbles`, **migration** depuis la 0.1.0 publiée). Un morceau garde sa clé `subsonic://acc/id` ; la copie sur le téléphone est une ligne `Offline` qui pointe vers le fichier. `MediaResolver.media()` préfère la copie. Les fichiers posés à la main sont lus par le `Scanner` du Mac, compte `local`, en lecture seule. Un petit canal natif `studio.lafleur/device` donne le dossier Musique d'Android et la place libre.

**Tech Stack:** Flutter 3.47.7, `drift` (migration 1→2), `http`, `flutter_taglib` (`TagLibIO` déjà là), `connectivity_plus` (BSD-3, Wi-Fi), `permission_handler` (MIT, Android audio), canal natif Swift/Kotlin.

**Spec:** `docs/conception/specs/2026-11-18-lafleurmusic-mobile-design.md` §1, 4.1, 4.2, 4.4, 4.6, 5, 8 · Maquettes : `maquettes/1-telephone-debout.png` (écrans 2 et 4 : bouton ⬇, ⬇ dans la liste, morceau grisé « pas sur le téléphone », menu « Garder sur mon iPhone » / « Sélectionner… »), `maquettes/2-coverflow-comptes.png` (écran 8).

**Hors de ce plan (plan 3) :** garder une playlist du serveur (+ fichier `.m3u8`) — les playlists du serveur arrivent au plan 3 ; fusion des comptes.

## Global Constraints

- Aucun visuel hors maquettes validées sans nouvelle maquette validée par Johnny. **L'écran « Sur mon iPhone » (liste de ce qui est gardé, échecs en rouge, réglage de la limite) n'a pas de maquette : tâche 9, étape 1 = maquette, puis on attend le oui de Johnny.**
- Couleurs et police du Mac : fond `#0D0D0D`, barres `#1C1C1C`, rose `#F26EF2`, Inter.
- Android 7+ (SDK 24), iOS 15+, iPhone seul, debout (R4 du plan 1).
- Textes FR / EN dans `lib/l10n/strings.dart` ; « iPhone » sur iOS, « téléphone » sur Android (`strings.onDevice(iphone)`).
- Les en-têtes HTTP du compte partent avec **toutes** les requêtes, téléchargements compris. Mots de passe, jetons, en-têtes : jamais dans un journal ni dans un message d'erreur (`SourceNetworkException`).
- Rangement : `LAFLEURMUSIC/<Artiste d'album>/<Album>/<NN> <Titre>.<ext>` ; iPhone : `Documents/LAFLEURMUSIC` (visible dans Fichiers) ; Android : `Music/LAFLEURMUSIC` (stockage partagé).
- L'appli n'efface **que** les fichiers qu’elle a téléchargés elle-même (ligne `Offline`). Fichiers posés à la main : lecture seule. Jamais rien d'effacé sur le serveur.
- Limite de place : 10 Go au départ, réglable de 1 Go à toute la place libre. Ce que l'utilisateur a gardé lui-même n'est jamais retiré tout seul.
- « À la maison » = Wi-Fi **et** le serveur répond. Top 100 automatique seulement à la maison ; ce que l'utilisateur lance part tout de suite (données mobiles comprises).
- Téléchargement : un morceau à la fois ; fichier `.part` puis renommé ; reprise au lancement suivant ; 3 échecs = rouge ; pas de téléchargement appli fermée.
- La base 0.1.0 déjà installée chez Johnny doit survivre : comptes, morceaux, écoutes gardés après la mise à jour.
- Commits en anglais, auteur `Jonlekern <288344322+Jonlekern@users.noreply.github.com>`, **sans** ligne Co-Authored-By ni mention d'IA.
- GitHub : branche `plan-2-offline`, envoi libre sur cette branche (accord de Johnny du 18.11.2026) ; jamais dans `main` ni de nouvelle version publiée sans son oui.
- Jamais la vraie bibliothèque ni le vrai Navidrome de Johnny : `test/fixtures/` et faux serveur (`integration_test/fake_subsonic.dart`).
- Aucun code d'Amperfy (GPL-3).

## Review Focus

1. **Noms de fichiers dangereux** : titre ou album avec `/ \ : * ? " < > |`, emoji, point final, 300 caractères, deux morceaux au même titre dans un album → un nom valide et unique sur iOS et Android, jamais hors de `LAFLEURMUSIC/` (`../`) — test en tâche 3.
2. **Appli tuée en plein téléchargement** : jamais un `.part` pris pour un morceau gardé ; au lancement suivant le `.part` est effacé et le morceau repart — test en tâche 4.
3. **Téléphone presque plein** alors que la limite n'est pas atteinte : refus avant de commencer, avec la place qu'il faudrait (la vraie place libre compte, pas seulement la limite) — test en tâche 4.
4. **Morceau gardé qui disparaît du serveur, ou compte supprimé** : le fichier reste sur le téléphone et joue encore (il devient un morceau `local`) ; rien n'est effacé tout seul — test en tâche 5.
5. **Mise à jour depuis la 0.1.0** : comptes, morceaux et écoutes intacts après la migration 1→2 — test en tâche 2.

---

### Task 1: Reprises du plan 1 (R8, R9)

**Files:**
- Modify: `lib/sources/subsonic.dart` (`test()`), `.github/workflows/ci.yml` (job `changes`)
- Test: `test/sources/subsonic_test.dart`

**Interfaces:**
- Produces: `test()` suit au plus 3 redirections **vers le même hôte** (y compris `http`→`https`, même port ou port par défaut) avec les mêmes en-têtes ; une redirection vers un autre hôte reste `headerRefused`. Si l'adresse finale est en `https` alors que le compte est en `http`, le résultat porte la nouvelle adresse : `Future<TestResult> test()` inchangé, plus `Uri? get redirectedBase` (null sans changement) que `AccountService.testDraft` montre via un nouveau texte `strings.useHttps` (« Le serveur demande https:// : adresse corrigée. » / « The server asks for https://: address fixed. ») et applique au brouillon.

- [ ] **Step 1:** tests `test()` : 301 `http://h:4533/rest/ping` → `https://h:4533/rest/ping` puis 200 ok → `ok` et `redirectedBase == https://h:4533` ; 302 vers `https://login.autre.com` → `headerRefused` ; 4 redirections en boucle → `headerRefused` ; en-têtes du compte présents sur chaque requête suivie.
- [ ] **Step 2:** lancer `flutter test test/sources/subsonic_test.dart` → échec.
- [ ] **Step 3:** suivre les redirections à la main (`followRedirects = false`, boucle ≤ 3).
- [ ] **Step 4:** `account_form.dart` : après « Tester », si `redirectedBase != null`, remplacer l'adresse du champ et montrer `strings.useHttps` (texte gris sous le champ, comme les autres messages : pas de nouveau visuel).
- [ ] **Step 5:** CI : `changes` compare à `git merge-base origin/main HEAD` sur une branche (et à `BEFORE` seulement sur `main`) ; le filtre devient `^(lib/|test/ui/|test/flutter_test_config.dart|test/tolerant_comparator.dart|assets/|pubspec\.(yaml|lock)|\.github/workflows/)`.
- [ ] **Step 6:** `flutter analyze` et `flutter test` (sans goldens) passent ; commit `fix: follow same-host redirects in server test; widen CI golden filter`.

### Task 2: Base v2 et réglages

**Files:**
- Modify: `lib/library/db.dart`, `lib/settings.dart`
- Create: `test/library/db_migration_test.dart`, `test/offline/offline_db_test.dart`

**Interfaces:**
- Produces (table `Offline`, `@DataClassName('OfflineRow')`) : `trackPath` (clé, = `Tracks.path`, ex. `subsonic://acc/id`), `filePath` (chemin du fichier final, relatif à la racine `LAFLEURMUSIC`), `size`, `addedAt` (ms), `reason` (`user` | `top100`), `state` (`queued` | `done` | `failed`), `failures` (int).
- Produces (table `PendingScrobbles`) : `id` auto, `accountId`, `remoteId`, `at` (ms).
- Produces (méthodes `LibraryDb`) : `Future<void> queueOffline(List<String> trackPaths, OfflineReason reason)` (ne rétrograde jamais `user` en `top100`) ; `Future<OfflineRow?> nextQueued()` (le plus ancien `queued` avec `failures < 3`) ; `Future<void> markOfflineDone(String trackPath, String filePath, int size)` ; `Future<void> markOfflineFailed(String trackPath)` (+1, `failed` à 3) ; `Future<void> removeOffline(List<String> trackPaths)` ; `Stream<Map<String, OfflineRow>> watchOffline()` ; `Future<OfflineRow?> offlineOf(String trackPath)` ; `Future<int> offlineBytes()` (somme des `done`) ; `Future<void> addPending(String accountId, String remoteId, DateTime at)` ; `Future<List<PendingScrobble>> pending(String accountId)` ; `Future<void> deletePending(List<int> ids)`.
- Produces : `schemaVersion => 2`, `onUpgrade` : `from < 2` → `createTable(offline)`, `createTable(pendingScrobbles)`.
- Produces (`AppSettings`) : `int storageLimitBytes` (défaut `10 * 1024 * 1024 * 1024`, lu/écrit dans `settings.json`, bornes appliquées par l'écran : 1 Go à la place libre).

- [ ] **Step 1:** test de migration : créer une base v1 (schéma du commit `ae39106`, table par table en SQL brut dans le test) avec un compte, 2 morceaux et une écoute ; l'ouvrir avec `LibraryDb` → compte, morceaux et écoute là, tables v2 vides et utilisables.
- [ ] **Step 2:** tests des méthodes ci-dessus (ordre de `nextQueued`, `failed` au 3e échec, `user` jamais rétrogradé, `offlineBytes` ne compte que `done`).
- [ ] **Step 3:** échec, puis implémentation, `dart run build_runner build`, tests verts.
- [ ] **Step 4:** commit `feat: database v2 with offline copies and pending scrobbles`.

### Task 3: Dossier LAFLEURMUSIC et noms de fichiers

**Files:**
- Create: `lib/offline/device.dart`, `lib/offline/paths.dart`, `ios/Runner/DeviceChannel.swift`, `android/app/src/main/kotlin/studio/lafleur/lafleurmusic/DeviceChannel.kt`
- Modify: `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist` (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` = true), `android/app/src/main/kotlin/.../MainActivity.kt`, `android/app/src/main/AndroidManifest.xml`
- Test: `test/offline/paths_test.dart`

**Interfaces:**
- Produces (`device.dart`, canal `studio.lafleur/device`) : `Future<Directory> musicRoot()` (iOS : `<Documents>/LAFLEURMUSIC` ; Android : `Environment.getExternalStoragePublicDirectory(DIRECTORY_MUSIC)/LAFLEURMUSIC`, créé au besoin) ; `Future<int> freeBytes(String path)` (iOS : `volumeAvailableCapacityForImportantUsage` ; Android : `StatFs.availableBytes`) ; `Future<void> announce(String path)` (Android : `MediaScannerConnection.scanFile` ; iOS : rien). Une interface `Device` pour que les tests la remplacent.
- Produces (`paths.dart`) : `String keptPath({required String albumArtist, required String album, int? disc, int? track, required String title, required String ext})` → chemin **relatif** ; `String safeName(String s)` (caractères interdits → `_`, espaces/points en fin retirés, vide → `_`, 120 octets UTF-8 max sans couper un caractère) ; `String uniquePath(String rel, bool Function(String) exists)` (ajoute ` (2)`, ` (3)`…). Numéro : `NN` sur 2 chiffres, `D-NN` si disque > 1, rien si inconnu.
- Android : `WRITE_EXTERNAL_STORAGE` `maxSdkVersion="28"`, `READ_EXTERNAL_STORAGE` `maxSdkVersion="32"`, `READ_MEDIA_AUDIO`, `requestLegacyExternalStorage="true"` (Android 10).

- [ ] **Step 1:** tests `paths_test.dart` avec les cas du point 1 de Review Focus (`AC/DC`, `Who?`, `Album.`, emoji, 300 caractères, `../../etc`, artiste vide → `Artiste inconnu`/`Unknown artist` via paramètre, doublons).
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** canal natif des deux côtés ; `flutter build ios --simulator --debug` et `flutter build apk --debug` compilent.
- [ ] **Step 4:** commit `feat: kept-file folder, safe file names and device channel`.

### Task 4: File de téléchargements

**Files:**
- Modify: `lib/sources/source.dart` (`Uri downloadUri(String songId)`), `lib/sources/subsonic.dart`, `lib/sources/account_service.dart` (`_CancellableSource`)
- Create: `lib/offline/downloader.dart`
- Test: `test/offline/downloader_test.dart`, `test/sources/subsonic_test.dart`

**Interfaces:**
- Consumes : tâches 2 et 3 ; `MediaResolver.source(accountId)` ; `TagLibIO` / `TagReader` (`lib/tags/`).
- Produces : `MusicSource.downloadUri(songId)` (Subsonic : `download`) ; `class Downloader extends ChangeNotifier` : `Downloader({required LibraryDb db, required MediaResolver resolver, required Device device, required Future<AppSettings> Function() settings, http.Client Function()? client, TagFileIO? tags})`, `Future<KeepResult> keep(List<Track> tracks, {OfflineReason reason = OfflineReason.user})` (refuse tout si `offlineBytes + taille > limite` ou `> freeBytes - 200 Mo` : `KeepResult.tooBig(neededBytes)`, sinon `KeepResult.queued(count, bytes)`), `void start()` (boucle, un à la fois), `void pause()`, `String? get current`, `double get progress`, `Future<void> resumeAtLaunch()` (efface les `*.part` sous la racine, remet en route les `queued`).
- Un morceau : GET `downloadUri` avec les en-têtes → si 4xx ou corps JSON d'erreur Subsonic, GET `streamUri` ; écrit `<final>.part`, `rename` ; extension = `suffix` du serveur, sinon `Content-Type` ; puis, si le fichier n'a ni titre ni pochette (`TagReader`), écrit titre / artiste / album / numéro / disque et la pochette 600 px (`remoteCover`) ; `device.announce` ; `markOfflineDone`. Erreur → `markOfflineFailed`, morceau suivant.

- [ ] **Step 1:** tests avec `MockClient` et un `Device` faux : `download` 200 → fichier rangé, `done` ; `download` 403/erreur 50 → repli `stream` ; en-têtes présents sur chaque requête ; coupure au milieu → pas de fichier final, `.part` effacé par `resumeAtLaunch`, morceau repris ; 3 échecs → `failed` ; limite dépassée et place libre trop petite → `tooBig` avec la bonne taille, rien en file ; un seul téléchargement à la fois.
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** commit `feat: one-at-a-time download queue with resume and space checks`.

### Task 5: Lire la copie, griser dehors, garder les fichiers orphelins

**Files:**
- Modify: `lib/player/media_resolver.dart`, `lib/player/player.dart` (saut), `lib/library/sync.dart` (`_removeUnseen`), `lib/sources/account_service.dart` (`remove`), `lib/library/db.dart`, `lib/player/loudness.dart`
- Test: `test/player/media_resolver_test.dart`, `test/library/sync_test.dart`, `test/player/player_offline_test.dart`

**Interfaces:**
- Consumes : `LibraryDb.offlineOf`, `musicRoot()`.
- Produces : `MediaResolver(…, {Future<String?> Function(String trackPath)? localCopy})` : copie `done` dont le fichier existe → `Media(cheminAbsolu)`, sans en-têtes ; sinon flux comme avant. `bool Function(Track) playable` exposé par `AccountService` (`playableNow`) : copie `done` **ou** compte joignable ; le `Player` saute un morceau non jouable au lieu de l'ouvrir (même chemin que « format illisible »), et passe au prochain morceau jouable.
- Produces : un morceau du serveur qui disparaît (synchro complète) ou dont le compte est supprimé **mais qui a une copie `done`** devient un morceau `local` : `path` = chemin absolu du fichier, `accountId = 'local'`, ligne `Offline` retirée (le fichier est alors « posé à la main » : lecture seule, jamais effacé) ; ses écoutes suivent (`movePlays`). Les autres disparaissent comme avant (R3 inchangé).
- Volume égal : un morceau joué depuis sa copie est mesuré (EBU R128) comme sur Mac ; ReplayGain du serveur sinon (R6 inchangé).

- [ ] **Step 1:** tests : copie présente → `Media` local ; copie `done` mais fichier effacé à la main → flux ; hors ligne, file [gardé, pas gardé, gardé] → le 2e est sauté ; synchro qui perd un morceau gardé → il reste, `local`, écoutes gardées ; suppression du compte → ses morceaux gardés restent.
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** commit `feat: play kept copies, skip unreachable tracks, keep orphaned files`.

### Task 6: Écoutes en attente

**Files:**
- Modify: `lib/library/play_counter.dart`, `lib/sources/account_service.dart`
- Test: `test/library/play_counter_test.dart`, `test/sources/account_service_test.dart`

**Interfaces:**
- Produces : `PlayCounter._scrobble` en échec → `db.addPending(acc, id, at)`. `AccountService` : après chaque `_check` ou synchro **ok** d'un compte, envoie ses écoutes en attente dans l'ordre (une requête `scrobble` par écoute, `time` = date d'origine), efface celles envoyées, s'arrête à la première erreur. Jamais deux envois en même temps pour un compte.

- [ ] **Step 1:** tests : serveur coupé → écoute en attente ; retour → envoyée avec la bonne date puis effacée ; erreur au milieu → les suivantes restent ; deux retours rapprochés → pas de doublon.
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** commit `feat: queue scrobbles offline and send them when the server is back`.

### Task 7: Fichiers posés à la main

**Files:**
- Modify: `lib/library/scanner.dart`, `lib/main.dart`
- Create: `lib/offline/local_folder.dart`
- Test: `test/offline/local_folder_test.dart`

**Interfaces:**
- Consumes : `Scanner`, `musicRoot()`, `LibraryDb.watchOffline`.
- Produces : `class LocalFolder` : `Future<void> rescan()` — lit `LAFLEURMUSIC/` (sauf `*.part` et les fichiers qui sont des copies `Offline`), ajoute/met à jour les morceaux `local` (clé = chemin absolu), retire ceux dont le fichier a disparu. Lancé au démarrage et au retour au premier plan. Android : demande la permission audio (`permission_handler`) la première fois, refus = on ne lit que nos propres fichiers, sans message bloquant.

- [ ] **Step 1:** tests (dossier temporaire) : un `.flac` posé → morceau `local` avec ses tags ; une copie gardée → pas de doublon ; fichier retiré → morceau retiré ; `.part` ignoré.
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** commit `feat: show music files placed by hand in the LAFLEURMUSIC folder`.

### Task 8: À la maison et Top 100 gardé tout seul

**Files:**
- Create: `lib/offline/home_state.dart`, `lib/offline/top_keeper.dart`
- Modify: `pubspec.yaml` (`connectivity_plus`), `lib/main.dart`
- Test: `test/offline/top_keeper_test.dart`, `test/offline/home_state_test.dart`

**Interfaces:**
- Produces : `class HomeState extends ChangeNotifier` : `bool get atHome` = Wi-Fi (`connectivity_plus`) **et** au moins un compte `connected` ; `Downloader` ne traite les `top100` que si `atHome` (les `user` partent toujours).
- Produces : `class TopKeeper` : `Future<void> refresh()` à chaque passage à `atHome = true` et après chaque écoute comptée : les 100 premiers du Top 100 (même calcul que `top_screen.dart`) qui ont un compte et pas de copie → `queueOffline(top100)` tant que la limite le permet (on s'arrête à la limite, sans erreur) ; une copie `top100` sortie du Top 100 → fichier effacé et ligne retirée ; une copie `user` jamais touchée.

- [ ] **Step 1:** tests : en données mobiles, rien ; à la maison, 3 morceaux du Top → en file `top100` ; limite atteinte → arrêt ; morceau sorti du Top gardé `top100` → effacé, gardé `user` → reste.
- [ ] **Step 2:** échec, implémentation, verts.
- [ ] **Step 3:** commit `feat: keep the Top 100 on the phone automatically at home`.

### Task 9: Écrans

**Files:**
- Modify: `lib/ui/track_menu.dart`, `lib/ui/phone/album_screen.dart`, `lib/ui/phone/home_screen.dart`, `lib/ui/track_list.dart`, `lib/l10n/strings.dart`
- Create: `lib/ui/phone/keep_screen.dart` (écran 8), `lib/ui/phone/on_device_screen.dart` (« Sur mon iPhone »), `maquettes/3-sur-mon-iphone.png` + `maquettes/src/3-sur-mon-iphone.html`
- Test: `test/ui/phone/keep_screen_test.dart`, `test/ui/phone/on_device_screen_test.dart`, goldens

**Interfaces:**
- Consumes : `Downloader.keep`, `KeepResult`, `LibraryDb.watchOffline`, `AccountService.playableNow`, `AppSettings.storageLimitBytes`, `freeBytes`.
- Produces (maquettes validées) : appui long → « Garder sur mon iPhone » ou « Retirer du téléphone » (copie `user`/`top100` → effacée) et « Sélectionner… » → écran 8 ; écran 8 : albums cochables, durée · taille, « déjà gardé », « Place sur l'iPhone : X utilisés sur Y · + Z », texte Fichiers, bouton « ⬇ Garder sur mon iPhone · Z » ; refus `tooBig` : message « Pas assez de place : il faut encore Z. » / « Not enough space: Z more needed. » ; bouton ⬇ de l'écran Album ; ⬇ rose après le nom d'un album gardé en entier ; dehors, morceau non jouable grisé avec « pas sur le téléphone ».
- Produces (**maquette d'abord**) : écran « Sur mon iPhone » (depuis l'Accueil) : téléchargement en cours avec sa progression, albums gardés (balayer ou appui long → Retirer), échecs en rouge avec « Réessayer », réglage de la limite (1 Go → place libre), chemin du dossier.

- [ ] **Step 1:** maquette HTML de l'écran « Sur mon iPhone » dans le style des maquettes 1-2, rendue en PNG ; **stop : la montrer à Johnny et attendre son oui** (sans oui, la tâche s'arrête à l'étape 4).
- [ ] **Step 2:** tests d'écran : menu Garder/Retirer selon l'état ; écran 8 coche, total, refus `tooBig` ; grisé hors ligne.
- [ ] **Step 3:** échec, implémentation, verts ; goldens écran 8 et morceau grisé (mode démo `LAFLEUR_DEMO_SCREEN`).
- [ ] **Step 4:** après le oui : écran « Sur mon iPhone » et ses tests/golden.
- [ ] **Step 5:** captures dans le simulateur montrées à Johnny ; commit `feat: keep screen, on-device screen and offline marks`.

### Task 10: Essai de bout en bout et documents

**Files:**
- Modify: `integration_test/app_test.dart`, `integration_test/fake_subsonic.dart` (`download` + coupure du serveur), `.github/workflows/ci.yml` (rien de neuf si `app_test` tourne déjà), `README.md`, `docs/conception/checklist.md`
- Test: `integration_test/offline_test.dart`

**Interfaces:**
- Consumes : tout le plan.

- [ ] **Step 1:** `offline_test.dart` : compte sur le faux serveur → garder un album → attendre `done` → fichier présent sous la racine → couper le faux serveur → l'album joue depuis la copie, un album non gardé est grisé ; une écoute faite coupé → le serveur la reçoit après le retour.
- [ ] **Step 2:** le faire passer dans le simulateur iPhone (`flutter test integration_test/offline_test.dart -d "iPhone LAFLEUR"`) et l'ajouter au job `android-emulator`.
- [ ] **Step 3:** pousser `plan-2-offline`, CI verte (tous les jobs).
- [ ] **Step 4:** README (statut « offline ») ; checklist mise à jour ; commit `docs: plan 2 offline status`.
