# LAFLEURMUSIC téléphone — plan 8 « file et bibliothèque » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** les six améliorations choisies après le comparatif Spotify (n° 1, 2, 5, 23, 24, 25) : une bulle qui confirme un ajout à la file, glisser à droite = Ajouter à la file, « Vider » qui ne retire que tes ajouts, le tri des albums gardé, « Écoutés récemment », et « Aller à l'album / l'artiste » depuis En cours.

**Architecture:** la file existe déjà (`lib/player/queue.dart` : `playNext`, `enqueue`, `addedCount`, `move`) ; on ajoute `clearAdded()` et on branche l'interface. Le tri est un réglage de `lib/settings.dart` (`settings.json`). « Écoutés récemment » se calcule depuis `PlayCounts.lastPlayed` (aucune table nouvelle), groupé par album fusionné (`albumMergeKey`).

**Tech Stack:** Flutter (`Dismissible` à deux sens, `SnackBar` / bulle maison), drift (requête sur `play_counts`).

**Spec:** spec §8 (« Améliorations choisies après le comparatif Spotify ») · Recherche : `docs/conception/recherche/comparatif-spotify.md` · Maquette validée : `maquettes/13-file-bibliotheque.png` (écrans A à D, oui de Johnny le 19.11.2026).

## Global Constraints

- Visuel : exactement la maquette 13. Bulle : « ✓ Ajouté à la file » + « Annuler » + « Voir la file », en bas au-dessus du mini-lecteur, partie seule après 4 s. Glisser à droite = « ＋ Ajouter à la file » (fond rose), à gauche = « Lire ensuite » (comme aujourd'hui).
- « Vider » (section « Ajoutés par toi ») : fenêtre « Vider tes ajouts ? » / « Les N morceaux que tu as ajoutés partent de la file. La suite de l'album reste. » / « Annuler » · « Vider ». La suite de l'album n'est jamais touchée ; le morceau en cours continue.
- Tri des albums : « Nom », « Artiste », « Ajout récent », « Plus écouté » ; gardé dans `settings.json` (clé `albumSort`), « Nom » par défaut. « Plus écouté » utilise les écoutes fusionnées du plan 3 (max(imported) + somme(count)).
- « Écoutés récemment » : les 10 derniers albums joués (un album = un `albumMergeKey`), le plus récent à gauche ; caché s'il est vide.
- Menu ⋯ de En cours : « Aller à l'album », « Aller à l'artiste » en tête.
- L'appli doit marcher **sans aucun compte** (seulement des fichiers sur le téléphone) : chaque fonction est testée aussi dans ce cas.
- Mode Classic (plan 6) : rien à dessiner ; « Écoutés récemment » n'y est pas ajouté dans ce plan.
- Mêmes textes en anglais dans `strings.dart`. Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-8-queue-library`.

## Review Focus

1. **« Annuler » après que le morceau ajouté a déjà commencé** (bulle encore visible) : rien ne casse, l'ajout joué n'est pas retiré du milieu — test en tâche 1.
2. **Glisser à droite sur un morceau absent** (compte coupé, pas de copie) : même règle que Lire ensuite aujourd'hui (grisé = pas d'ajout, petit message) — test en tâche 1.
3. **« Vider » quand il n'y a aucun ajout** : bouton caché ; et pendant le fondu enchaîné vers un ajout — test en tâche 2.
4. **Tri « Plus écouté » avec 5 000 albums** : pas de saccade (requête unique, pas une par album) — test en tâche 3.
5. **Album écouté sur deux comptes** : une seule vignette dans « Écoutés récemment » — test en tâche 3.

---

### Task 1: Ajouter à la file : glisser à droite + bulle

**Files:** Modify `lib/ui/track_list.dart` (ou l'endroit du `Dismissible` actuel), `lib/ui/phone/album_screen.dart`, `lib/ui/phone/playlist_screen.dart`, `lib/ui/track_menu.dart`, `lib/l10n/strings.dart` · Create `lib/ui/queue_toast.dart` · Test `test/ui/queue_toast_test.dart`, widget, golden (écran A)

**Interfaces:**
- Produces : `showQueueToast(BuildContext, {required int count, required VoidCallback onUndo, required VoidCallback onShowQueue})` ; `PlayQueue.removeLastAdded(List<T> items)` pour « Annuler » (retire ces ajouts s'ils ne sont pas encore joués).

- [ ] Step 1: tests (glisser droite → `enqueue`, gauche → `playNext` inchangé, bulle 4 s, Annuler, Voir la file ouvre l'onglet À suivre, points 1-2). Échec, implémentation, verts ; golden = maquette 13 A. Commit `feat: swipe right to add to queue, with a confirmation bubble`.

### Task 2: « Vider » ne retire que tes ajouts

**Files:** Modify `lib/player/queue.dart`, `lib/player/player.dart`, `lib/player/mpv_port.dart` (si la file mpv doit suivre), `lib/ui/phone/now_screen.dart` · Test `test/player/queue_test.dart`, widget, golden (écran C)

**Interfaces:**
- Produces : `PlayQueue.clearAdded()` (retire tous les ajouts à venir, garde la suite) ; `Player.clearAdded()` qui garde mpv aligné.

- [ ] Step 1: tests (ajouts retirés, suite gardée, morceau en cours intact, fenêtre de confirmation, point 3). Échec, implémentation, verts. Commit `feat: clear only your additions from the queue`.

### Task 3: Tri des albums gardé et « Écoutés récemment »

**Files:** Modify `lib/settings.dart`, `lib/library/db.dart` (requêtes), `lib/library/library_view.dart`, `lib/ui/phone/home_screen.dart` (ou l'écran Albums), `lib/l10n/strings.dart` · Test `test/library/library_view_test.dart`, `test/settings_test.dart`, widget, golden (écran B)

**Interfaces:**
- Produces : `enum AlbumSort { name, artist, recent, mostPlayed }` ; `Settings.albumSort` ; `LibraryView.albums(sort:)` ; `LibraryView.recentAlbums({int limit = 10})` (par `albumMergeKey`, `MAX(last_played)`).

- [ ] Step 1: tests (chaque tri, réglage relu au redémarrage, points 4-5, sans compte). Échec, implémentation, verts. Commit `feat: kept album sort and recently played`.

### Task 4: « Aller à l'album / l'artiste » depuis En cours

**Files:** Modify `lib/ui/phone/now_screen.dart`, `lib/ui/now_playing_screen.dart` (tablette), `lib/l10n/strings.dart` · Test widget, golden (écran D)

- [ ] Step 1: tests (ouvre le bon album fusionné, l'artiste ; morceau local sans album ; tablette). Échec, implémentation, verts. Commit `feat: go to album or artist from Now Playing`.

### Task 5: Bout en bout et documents

**Files:** Modify `integration_test/app_test.dart` (ou nouveau test), `README.md`, `docs/conception/checklist.md`

- [ ] Step 1: bout en bout sur le simulateur iPhone : glisser à droite, bulle, Annuler, Vider, tri gardé après relance ; job Android ; CI verte.
- [ ] Step 2: README (anglais) et checklist (français). Commit `docs: plan 8 status`.
