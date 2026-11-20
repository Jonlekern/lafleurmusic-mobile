# LAFLEURMUSIC téléphone — plan 10 « musique dans l'appli seulement » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dans Réglages › Sur mon iPhone, un choix « Où garder la musique » : « Dans un dossier visible » (aujourd'hui, par défaut) ou « Dans l'appli seulement » (cachée, partie avec l'appli quand on la supprime).

**Architecture:** aujourd'hui une seule racine (`Device.musicRoot()`) sert aux morceaux gardés **et** aux fichiers posés à la main. Elle se coupe en deux : `keptRoot()` (où le téléchargeur écrit : le dossier visible, ou un dossier privé de l'appli) et `visibleRoot()` (ce que `LocalFolder` relit : toujours le dossier visible). Passer d'un mode à l'autre réutilise `Downloader.moveRoot` (copie, puis effacement, place vérifiée avant). Les `.m3u8` des playlists gardées suivent les morceaux gardés.

**Tech Stack:** Flutter, `path_provider`, canal natif `DeviceChannel` (Swift / Kotlin), drift.

**Spec:** `docs/conception/specs/2026-11-18-lafleurmusic-mobile-design.md` §« Dossier choisi par l'utilisateur » + demande de Johnny du 20.11.2026 (« télécharger la musique que dans l'app, et quand l'app est supprimée la musique part avec »). Maquette validée : `maquettes/17-ou-garder.png` (Johnny « Oui », 20.11.2026).

## Global Constraints

- Par défaut : « Dans un dossier visible », comme aujourd'hui. Rien ne bouge chez quelqu'un qui ne touche à rien.
- Dossier privé : iPhone `Library/Application Support/LAFLEURMUSIC`, **exclu de la sauvegarde iCloud** (`isExcludedFromBackup`, la musique se re-télécharge) ; Android `getExternalFilesDir(Environment.DIRECTORY_MUSIC)/LAFLEURMUSIC` (effacé à la désinstallation, aucune permission, jamais annoncé à la médiathèque Android).
- Les fichiers posés à la main ne sont **jamais** déplacés, écrits ni effacés ; ils jouent toujours depuis le dossier visible.
- Changer de mode = question d'abord (maquette 17 B), puis déplacement copie-puis-effacement avec la place vérifiée avant ; « Annuler » = rien ne bouge. Revenir au dossier visible = retour au dossier choisi avant (réglage `musicFolder` gardé), ou celui par défaut s'il ne répond plus.
- Textes (maquette 17) : section « OÙ GARDER LA MUSIQUE » à la place de « DOSSIER » ; « Dans un dossier visible » — « Tu la vois dans l'app Fichiers. Elle reste si tu supprimes l'appli. » ; « Dans l'appli seulement » — « Cachée. Elle part avec l'appli quand tu la supprimes. » ; pied « En changeant, les morceaux gardés sont déplacés. Les fichiers que tu poses toi-même dans LAFLEURMUSIC jouent toujours. » ; question « Ranger ta musique dans l'appli ? » / « Les {taille} gardés quittent le dossier LAFLEURMUSIC et vont dans l'appli. Si tu supprimes l'appli, ils partent avec. » / Annuler · Déplacer. Android : « Sur mon téléphone », « l'app Fichiers » → « tes fichiers », dossier « Musique › LAFLEURMUSIC ». Textes anglais aussi.
- Mode sombre et mode clair (plan 7) : goldens des deux.
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-10-in-app`.

## Review Focus

1. **Un téléchargement en cours pendant le changement** : il s'arrête proprement et reprend dans le nouveau dossier, sans fichier à moitié laissé — test tâche 2.
2. **Pas assez de place** pour la copie : refus clair, rien n'a bougé — test tâche 2.
3. **L'appli tuée pendant le déplacement** : au lancement suivant, chaque morceau est dans l'un des deux dossiers et la base pointe dessus ; rien de perdu — test tâche 2.
4. **Un dossier iCloud / choisi** était actif avant « Dans l'appli seulement » : la musique en part, et le retour la remet dans ce dossier — test tâche 2.
5. **Un fichier posé à la main** dans le dossier visible : jamais déplacé, toujours listé dans les deux modes — test tâche 2.

---

### Task 1: Deux racines et le dossier privé

**Files:** Modify `lib/offline/device.dart`, `lib/settings*` (réglage `keepInApp`, défaut `false`), `ios/Runner/DeviceChannel.swift`, `android/app/src/main/kotlin/studio/lafleur/lafleurmusic/DeviceChannel.kt`, `lib/offline/local_folder.dart` · Test `test/offline/device_roots_test.dart`

**Interfaces:**
- Produces: `Device.keptRoot()` (remplace `musicRoot()` pour le téléchargeur et les `.m3u8`), `Device.visibleRoot()` (pour `LocalFolder` et « Choisir le dossier… »), `Device.privateRoot()`, `Device.setKeepInApp(bool)` (appelé dans le `commit` du déplacement) ; clé de chemin `app://` pour les fichiers du dossier privé (comme `docs://`, survit au changement de conteneur iOS).

- [ ] Step 1: tests : par défaut `keptRoot == visibleRoot` ; avec `keepInApp` `keptRoot == privateRoot` et `visibleRoot` inchangé ; `keyFor`/`absolutePath` aller-retour pour `app://` ; `announce` ne fait rien pour un chemin privé ; le dossier privé iOS est marqué exclu de la sauvegarde (canal). Échec, implémentation, verts. Commit `feat: a private folder inside the app for kept songs`.

### Task 2: Déplacer entre les deux

**Files:** Modify `lib/offline/downloader.dart` (réutiliser `moveRoot`), `lib/offline/m3u.dart`, `lib/offline/local_folder.dart` · Test `test/offline/move_to_app_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces: `Downloader.moveKept({required bool toApp})` → `KeepResult` (ok, refus place, échec).

- [ ] Step 1: tests des points 1 à 5 de la Review Focus, et : aller puis retour remet chaque fichier gardé et chaque `.m3u8` au même chemin relatif ; la place demandée = somme des fichiers gardés. Échec, implémentation, verts. Commit `feat: move kept songs into the app and back`.

### Task 3: L'écran (maquette 17)

**Files:** Modify `lib/ui/phone/on_device_screen.dart`, `lib/l10n/strings.dart` · Test widget + goldens `phone-17a/b/c` sombre et `-light`

- [ ] Step 1: tests : les deux cartes, la carte choisie en rose, « Choisir le dossier… » seulement dans la carte visible quand elle est choisie ; la question avant de déplacer, « Annuler » ne déplace rien ; textes iPhone / Android. Goldens comparés à la maquette 17. Commit `feat: choose where kept songs live`.

### Task 4: Bout en bout et docs

- [ ] Step 1: essai d'intégration (simulateur privé iOS + émulateurs Android de la CI) : garder un album, passer « Dans l'appli seulement », le dossier visible n'a plus le morceau, il joue hors ligne, retour au dossier visible. Commit `test: kept songs move into the app and back`.
- [ ] Step 2: README, checklist, addendum à la spec (§ dossier). CI verte. Commit `docs: plan 10 status`.
