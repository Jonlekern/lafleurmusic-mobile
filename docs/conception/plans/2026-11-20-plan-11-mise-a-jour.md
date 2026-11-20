# LAFLEURMUSIC téléphone — plan 11 « mise à jour depuis l'appli » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'appli voit seule qu'une nouvelle version existe sur GitHub et aide à l'installer : sur Android, un bouton télécharge puis Android demande « Installer ? » ; sur iPhone, l'appli ouvre le fichier IPA dans Safari (signé ensuite avec Signulous).

**Architecture:** un `UpdateService` (Dart pur, client `http` injecté) lit `https://api.github.com/repos/Jonlekern/lafleurmusic-mobile/releases/latest`, compare `tag_name` à `appVersion`, garde la date du dernier essai et la version écartée dans les réglages. Android : téléchargement de l'APK dans le cache de l'appli, empreinte SHA-256 vérifiée contre le `digest` de GitHub, puis le canal natif `studio.lafleur/device` ouvre l'installeur Android (`FileProvider`). iPhone : `url_launcher` ouvre l'URL de l'IPA dans Safari. L'interface : bandeau sur l'Accueil, feuille, ligne dans Réglages, ligne « Mise à jour » en haut du menu Classic.

**Tech Stack:** Flutter, `http`, `crypto`, `url_launcher`, Kotlin `FileProvider` + `ACTION_VIEW`.

**Spec:** demande de Johnny du 20.11.2026 (« mettre l'app à jour depuis l'app, sans devoir la retélécharger à chaque fois ») ; maquette validée `maquettes/19-mise-a-jour.png` (Johnny « Oui », 20.11.2026).

## Global Constraints

- Seulement sur iOS et Android (ailleurs : rien, ni bandeau ni ligne).
- Vérification automatique **une fois par jour au plus** (au lancement, si le dernier essai a plus de 24 h) ; rien de l'utilisateur n'est envoyé (requête GET anonyme, `User-Agent: LAFLEURMUSIC/<version>`). Pas de réseau / erreur / limite GitHub : silence, rien n'est affiché, nouvel essai au lancement suivant.
- Une version est « nouvelle » si `tag_name` (sans le `v`) est plus grande que `appVersion` en comparant les trois nombres (0.10.2 < 0.11.0 < 1.0.0). Brouillons et pré-versions ignorés (`/releases/latest` les exclut déjà).
- ✕ sur le bandeau = plus de bandeau pour **cette** version (réglage `dismissedUpdate`) ; une version plus récente le ramène. La ligne Réglages marche toujours.
- Textes (maquette 19) : bandeau « Nouvelle version {v} » / « Touche pour voir ce qui change » / bouton « Mettre à jour » / « ✕ ». Feuille : « LAFLEURMUSIC {v} », « Tu as la {appVersion} », puis ce qui change (la section « What's new » du texte de la version GitHub, en liste ; si absente : les premières lignes de texte). Android : bouton « Télécharger et installer · {taille Mo} », pendant le téléchargement une barre + « {n} % », dessous « Ta musique, tes playlists et tes comptes restent. ». iPhone : bouton « Ouvrir le téléchargement », dessous « Le fichier s'ouvre dans Safari. Signe-le avec Signulous comme d'habitude. » puis « Ta musique, tes playlists et tes comptes restent. ». Réglages (en bas) : ligne « Version {appVersion} » et ligne « Chercher une mise à jour › » ; résultat de la recherche manuelle : la feuille si nouvelle version, sinon « Tu as la dernière version », sans réseau « Pas de réseau, réessaie plus tard ». Classic : une ligne « Mise à jour » en haut du menu principal quand une nouvelle version existe (non écartée), qui ouvre la même feuille. Textes anglais aussi (« New version {v} », « Update », « Download and install · {n} MB », « Open the download », « You have the latest version »…).
- Android : l'APK doit venir de l'asset nommé exactement `LAFLEURMUSIC-android.apk` de cette version ; taille et `digest` (`sha256:…`) vérifiés avant d'ouvrir l'installeur ; fichier gardé dans le cache de l'appli (`updates/`), effacé au lancement suivant. Échec (réseau coupé, empreinte fausse) : message « Le téléchargement a échoué. Réessaie. » et le bouton revient. Permission `REQUEST_INSTALL_PACKAGES` + `FileProvider` (autorité `${applicationId}.updates`, chemin cache `updates/`).
- iPhone : asset `LAFLEURMUSIC-iphone-unsigned.ipa`, ouvert avec `LaunchMode.externalApplication`. Pas d'asset : la page de la version (`html_url`).
- Couleurs : rose #F26EF2, fonds #0D0D0D / #1C1C1C, bandeau fond #2a1530 bord rose (mode clair : couleurs via `context.colors`, pas de couleur en dur hors `lib/theme/colors.dart`). Goldens sombre et `-light`.
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `in-app-update`.

## Review Focus

1. **Pas de réseau / GitHub répond 403 (limite) ou un JSON inattendu** : aucun plantage, aucun bandeau ; l'essai raté compte comme l'essai du jour (on ne martèle pas GitHub) et le lendemain on réessaie — test tâche 1.
2. **Même version ou version plus ancienne publiée** (`v0.10.2` quand on a 0.10.2, ou `v0.9.9`) : pas de bandeau ; « 0.10.10 » est bien plus grand que « 0.10.9 » — test tâche 1.
3. **Téléchargement coupé ou fichier corrompu** : l'installeur ne s'ouvre jamais sur un APK incomplet ou dont l'empreinte ne correspond pas ; le bouton revient — test tâche 1.
4. **L'utilisateur quitte la feuille pendant le téléchargement** : le téléchargement s'arrête, pas d'installeur qui surgit plus tard, pas d'erreur `setState` après `dispose` — test tâche 3.
5. **Mode Classic** : la ligne « Mise à jour » n'apparaît que s'il y a une nouvelle version, et la molette navigue dessus comme sur les autres lignes — test tâche 3.

---

### Task 1: Le service de mise à jour

**Files:** Create `lib/update/update_service.dart` · Modify `lib/settings.dart` (`lastUpdateCheck` en ms epoch, `int?` ; `dismissedUpdate`, `String?` ; chargés/enregistrés comme les autres) · Test `test/update/update_service_test.dart`

**Interfaces:**
- Produces:
  - `class UpdateInfo { final String version; final List<String> notes; final String pageUrl; final String? apkUrl; final int? apkSize; final String? apkSha256; final String? ipaUrl; }`
  - `bool isNewerVersion(String candidate, String current)`
  - `class UpdateService { UpdateService({required http.Client client, required AppSettings settings, required Future<void> Function() saveSettings, DateTime Function()? now, String current = appVersion}); final ValueNotifier<UpdateInfo?> available; Future<UpdateInfo?> checkDaily(); Future<UpdateCheck> checkNow(); void dismiss(UpdateInfo u); Future<File> downloadApk(UpdateInfo u, Directory cacheDir, {void Function(double)? onProgress, CancelToken? cancel}); static Future<void> clearDownloads(Directory cacheDir); }`
  - `enum UpdateCheck { newer, upToDate, offline }` (`checkNow` remplit aussi `available`)
  - `available` vaut l'info seulement si elle est plus récente **et** pas écartée (`dismiss` la remet à null et enregistre).

- [ ] Step 1: tests (client `http` `MockClient`) : JSON réel de `/releases/latest` (fixture avec `tag_name`, `html_url`, `body` contenant `## What's new in 0.11.0` + puces, deux assets avec `size` et `digest`) → `UpdateInfo` complet, notes = les puces sans `- ` ni `**` ; `isNewerVersion` (0.11.0>0.10.2, 0.10.10>0.10.9, 0.10.2 pas >0.10.2, 1.0.0>0.99.99, tag `v` accepté, texte invalide → false) ; `checkDaily` ne fait aucune requête si le dernier essai < 24 h, en fait une sinon et enregistre la date même en cas d'échec ; 403, timeout, JSON cassé → `null`, pas d'exception ; version écartée → `available` reste null ; `checkNow` → `newer` / `upToDate` / `offline` ; `downloadApk` : progression croissante jusqu'à 1, fichier dans `updates/`, taille ou SHA-256 faux → exception et fichier effacé, `cancel` → arrêt et fichier effacé ; `clearDownloads` vide `updates/`.
- [ ] Step 2: implémentation, tests verts, `flutter analyze` propre. Commit `feat: check GitHub for a new version`.

### Task 2: L'installeur Android

**Files:** Modify `android/app/src/main/AndroidManifest.xml` (permission `REQUEST_INSTALL_PACKAGES`, `<provider androidx.core.content.FileProvider>` autorité `${applicationId}.updates`), Create `android/app/src/main/res/xml/update_paths.xml` (`<cache-path name="updates" path="updates/"/>`), Modify `DeviceChannel.kt` (méthode `installApk` {`path`: String} → ouvre `Intent.ACTION_VIEW` type `application/vnd.android.package-archive`, `FLAG_GRANT_READ_URI_PERMISSION | FLAG_ACTIVITY_NEW_TASK` ; renvoie `false` si le fichier n'existe pas ou hors `cacheDir/updates`), `lib/offline/device.dart` (`Future<bool> installApk(String path)` ; iOS et ailleurs → `false`) · Test `test/offline/device_install_test.dart` (canal simulé : nom de méthode et argument) ; build CI `android` vert.

- [ ] Step 1: test canal, implémentation Dart + Kotlin + manifest, `flutter build apk --debug` local si possible sinon CI. Commit `feat: open the Android installer for a downloaded update`.

### Task 3: L'interface (maquette 19)

**Files:** Create `lib/ui/update_sheet.dart` (feuille + bandeau), Modify `lib/ui/phone/home_screen.dart` (bandeau en haut de l'Accueil quand `available` n'est pas null), `lib/ui/phone/accounts_screen.dart` (lignes « Version » et « Chercher une mise à jour » en bas de Réglages), `lib/ui/classic/…` (ligne « Mise à jour » en haut du menu principal), `lib/l10n/strings.dart`, `lib/app_scope.dart` (`UpdateService? update`), `lib/main.dart` (créer le service sur iOS/Android, `clearDownloads` puis `checkDaily` au lancement, sans bloquer le démarrage) · Test widget `test/ui/phone/update_widget_test.dart` + goldens `phone-19a` (Accueil avec bandeau), `phone-19b` (feuille Android avec barre à 62 %), `phone-19c` (feuille iPhone), sombre et `-light`.

- [ ] Step 1: tests : bandeau absent sans mise à jour, présent avec ; ✕ appelle `dismiss` et le bandeau part ; « Mettre à jour » et toucher le bandeau ouvrent la feuille ; feuille Android : bouton → progression → `installApk` appelé avec le fichier ; échec → message et bouton revient ; fermer la feuille pendant le téléchargement annule (Review Focus 4) ; feuille iPhone : bouton → `launchUrl` sur l'URL de l'IPA en `externalApplication` (lanceur injectable) ; Réglages « Chercher une mise à jour » → feuille / « Tu as la dernière version » / « Pas de réseau, réessaie plus tard » ; Classic : ligne « Mise à jour » seulement avec une mise à jour, molette + bouton central l'ouvrent. Goldens comparés à la maquette 19.
- [ ] Step 2: implémentation, tests et goldens verts. Commit `feat: update the app from inside the app`.
