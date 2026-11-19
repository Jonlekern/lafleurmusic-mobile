# LAFLEURMUSIC téléphone — plan 3 « plusieurs comptes » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** plusieurs comptes vus un par un, tous fusionnés ou en fusion « Perso » ; un même album sur deux comptes n'apparaît qu'une fois et joue depuis la meilleure source ; les playlists du serveur sous les albums (gardables) ; le Cover Flow quand on couche le téléphone ; la disposition en colonnes du Mac sur tablette.

**Architecture:** la base passe en version 3 (table `Playlists`, `PlayCounts` séparé en écoutes importées du serveur + écoutes de l'appli, réglages d'affichage). Une clé de fusion `mergeKey(track)` = `albumKey` + titre + numéro, sans accents ni casse. La `library` filtre et regroupe selon le mode d'affichage ; l'écran ne sait jamais d'où vient un morceau. Au moment de jouer, `MediaResolver` choisit la source : copie gardée, sinon le premier compte joignable dans l'ordre de l'écran 6.

**Tech Stack:** Flutter 3.47.7, `drift` (migration 2→3), Subsonic `getPlaylists` / `getPlaylist`, `OrientationBuilder`, écrans du Mac (`coverflow_screen.dart`, `library_screen.dart`).

**Spec:** `docs/conception/specs/2026-11-18-lafleurmusic-mobile-design.md` §1, 2, 4.1, 4.3, 4.5, 8 (playlists du serveur, nombres d'écoutes) · Maquettes : `maquettes/1-telephone-debout.png` (écran 1 : puces « Tout ▾ / Navidrome / Jellyfin »), `maquettes/2-coverflow-comptes.png` (écran 5 Cover Flow couché, écran 6 Comptes + Affichage).

## Global Constraints

- Aucun visuel hors maquettes validées sans nouvelle maquette validée par Johnny. La section « Playlists du serveur » et l'écran d'une playlist suivent `maquettes/7-playlists.png` (écrans 10-11, **validée par Johnny le 18.11.2026**). La tablette reprend la disposition de l'appli Mac (déjà validée sur Mac) avec les écrans Comptes / Sur mon iPhone du téléphone.
- Couleurs et police : fond `#0D0D0D`, barres `#1C1C1C`, rose `#F26EF2`, Inter (le mode clair est le plan 7).
- Android 7+ (SDK 24), iOS 15+. La tablette (iPad, Android ≥ 900 px de large) est ajoutée dans ce plan ; le téléphone reste debout sauf la bibliothèque, qui se couche en Cover Flow.
- Textes FR / EN dans `lib/l10n/strings.dart` ; « iPhone » sur iOS, « téléphone » sur Android.
- Même album = même artiste d'album + même nom d'album, sans accents ni casse (`albumKey`) ; même morceau = même `albumKey` + titre + numéro (sans accents ni casse).
- Source jouée : copie gardée sur le téléphone, sinon le premier compte **joignable** dans l'ordre de l'écran 6. Une écoute est comptée (et envoyée) sur le compte qui a joué.
- Nombres d'écoutes : au départ, pour un morceau présent sur deux comptes, on garde le plus grand des nombres donnés par les serveurs ; ensuite chaque écoute faite dans l'appli s'ajoute.
- Playlists du serveur : jamais fusionnées entre comptes ; en mode Tout / Perso, chacune porte le nom de son compte en petit ; lecture seule. Garder une playlist = garder ses morceaux (rangés Artiste/Album) + un fichier `<dossier>/Playlists/<Nom>.m3u8` qui donne l'ordre.
- Fichiers posés à la main : apparaissent toujours, quel que soit le mode.
- La base 0.1.0 et la base du plan 2 doivent survivre (migration 1→3 et 2→3).
- Commits en anglais, auteur `Jonlekern <288344322+Jonlekern@users.noreply.github.com>`, sans Co-Authored-By ni mention d'IA. Branche `plan-3-accounts`, envoi libre sur cette branche ; jamais `main` ni de version publiée sans le oui de Johnny.
- Jamais la vraie bibliothèque ni le vrai Navidrome de Johnny dans les tests.

## Review Focus

1. **Le même album sur deux comptes, l'un absent** : affiché une fois, joue depuis le compte présent ; si les deux sont absents et rien n'est gardé, grisé — test en tâche 2.
2. **Noms presque pareils** (`Beyoncé` / `Beyonce`, `The Album` / `the album`, espaces doubles) : fusionnés ; deux albums différents du même nom chez deux artistes : **pas** fusionnés — test en tâche 1.
3. **Nombres d'écoutes** : un morceau à 12 écoutes sur un serveur et 7 sur l'autre affiche 12 ; une écoute dans l'appli → 13 ; une resynchro du serveur ne remet pas 12 — test en tâche 3.
4. **Playlist avec un morceau absent de son compte, ou deux fois le même morceau** : l'ordre est gardé, le doublon joue deux fois, l'absent est grisé ; le `.m3u8` reste valide — test en tâche 5.
5. **Téléphone couché pendant la lecture sur En cours** : rien ne bascule (pas de Cover Flow sur En cours) ; couché sur l'Accueil → Cover Flow, relevé → retour au même endroit — test en tâche 6.

---

### Task 1: Clé de fusion et base v3

**Files:** Modify `lib/library/db.dart`, `lib/library/models.dart`, `lib/settings.dart` · Create `lib/library/merge.dart` · Test `test/library/merge_test.dart`, `test/library/db_migration_test.dart`

**Interfaces:**
- Produces : `String mergeKey(Track t)` (dans `merge.dart`, réutilise `sortKey` de la base pour accents/casse ; `albumKey` + `\u0000` + titre normalisé + `\u0000` + numéro ou vide).
- Produces : colonne `Tracks.mergeKey` (texte, indexée), remplie par `upsertTracks` ; table `Playlists` (`accountId`, `remoteId`, `name`, `position`, clé `accountId+remoteId`) et `PlaylistItems` (`accountId`, `playlistId`, `index`, `trackPath`) ; `PlayCounts` gagne `imported` (int, défaut 0) — `count` reste les écoutes faites dans l'appli.
- Produces : `schemaVersion => 3`, `onUpgrade` : `from < 2` (tables du plan 2) puis `from < 3` (nouvelles colonnes/tables, `mergeKey` recalculé pour toutes les lignes, les `count` existants venant d'un serveur passent dans `imported` : la sync du plan 1 utilisait `raisePlayCounts`, donc `imported = count`, `count = 0`).
- Produces (`AppSettings`) : `DisplayMode displayMode` (`one` | `all` | `custom`, défaut `all`), `String? oneAccount`, `List<String> customAccounts`.

- [ ] Step 1: tests `mergeKey` (cas du point 2 de Review Focus) ; tests migration 1→3 et 2→3 (comptes, morceaux, copies gardées, écoutes intactes ; `imported`/`count` comme ci-dessus).
- [ ] Step 2: échec, implémentation, `build_runner`, verts. Commit `feat: merge key and database v3`.

### Task 2: Vue fusionnée et meilleure source

**Files:** Modify `lib/library/db.dart` (requêtes `watchAlbums`, `watchAlbumTracks`, `watchArtistTracks`, `watchGenreTracks`, `watchAllTracks`, `search`, `top`), `lib/player/media_resolver.dart`, `lib/sources/account_service.dart` (`playableNow`) · Create `lib/library/library_view.dart` · Test `test/library/library_view_test.dart`, `test/player/media_resolver_test.dart`

**Interfaces:**
- Produces : `class LibraryView` (lit le mode et l'ordre des comptes) : `Set<String> visibleAccounts` ; les requêtes ne renvoient que les comptes visibles + `local`, **une ligne par `mergeKey`** (la ligne choisie = copie gardée, sinon premier compte dans l'ordre).
- Produces : `MediaResolver.media(path)` : si le morceau a des jumeaux (même `mergeKey`) : copie gardée de n'importe lequel → fichier ; sinon premier compte **joignable** (`AccountService.stateOf != absent`, règle P8 du plan 2) dans l'ordre → son flux ; la clé réellement jouée est donnée au `PlayCounter` (écoute comptée et envoyée sur ce compte).
- Produces : `playableNow` vrai si un des jumeaux est jouable.

- [ ] Step 1: tests : même album sur A et B → une fois ; A absent → joue B ; copie gardée sur B → fichier ; mode Un compte = seulement A (+ local) ; Perso = cochés ; l'écoute part sur le compte qui a joué.
- [ ] Step 2: échec, implémentation, verts. Commit `feat: merged library view and best-source playback`.

### Task 2b: Chargement fiable après l'ajout d'un compte (retour de Johnny, 19.11.2026)

Johnny a ajouté son compte Navidrome dans la 0.2.0 : « connecté », mais aucune musique ; il a fallu tirer la liste vers le bas pour qu'elle apparaisse.

**Files:** Modify `lib/sources/account_service.dart`, `lib/library/sync.dart` · Test `test/sources/account_service_test.dart`, `test/library/sync_test.dart`

**Interfaces:**
- Produces : après l'ajout (ou la modification) d'un compte, une synchro tout de suite, **puis une deuxième 30 secondes plus tard** (demande de Johnny), et encore une si la précédente n'était pas complète (au plus 3 essais rapprochés) ; rien en double si une synchro tourne déjà.
- Produces : un album qui ne se lit pas (`albumSongs` en erreur, réponse bizarre) est sauté ; les autres sont enregistrés ; la synchro est marquée incomplète (rien n'est effacé, règle R3) et réessayée.
- Produces : la cause de l'échec de la première synchro est cherchée et notée dans le rapport (permission réseau local iOS refusée au premier essai ? synchro lancée avant la fin de l'enregistrement du compte ?).

- [ ] Step 1: tests (synchro relancée après 30 s avec une horloge simulée ; un album en erreur n'empêche pas les autres ; pas de double synchro). Échec, implémentation, verts. Commit `fix: load the library reliably after adding an account`.

### Task 2c: Confirmer avant de retirer du téléphone (demande de Johnny, 19.11.2026)

Maquette validée : `maquettes/10-confirmer-retirer.png` (écrans 12 et 12b).

**Files:** Modify `lib/ui/keep_actions.dart`, `lib/ui/phone/on_device_screen.dart`, `lib/settings.dart`, `lib/l10n/strings.dart` · Test widget + goldens

**Interfaces:**
- Produces : avant chaque « Retirer du téléphone » voulu par l'utilisateur (appui long, glisser dans Sur mon iPhone), une fenêtre « Retirer du téléphone ? » / « Remove from the iPhone/phone? » : « « <nom> » (<N> morceaux, <taille>) sera effacé de ton iPhone. Il reste sur ton serveur : tu pourras le garder à nouveau. » (« téléphone » sur Android ; EN équivalent), case « Ne plus me demander », boutons « Annuler » / « Retirer ». Annuler ne touche à rien.
- Produces : `AppSettings.confirmRemove` (bool, défaut vrai) ; la case cochée + Retirer le met à faux ; dans « Sur mon iPhone », section « CONFIRMATIONS » avec l'interrupteur « Demander avant de retirer » et le texte « Si tu as coché « Ne plus me demander », rallume-le ici. ».
- Les retraits automatiques (Top 100) ne demandent jamais.

- [ ] Step 1: tests (fenêtre affichée, Annuler ne retire rien, Retirer retire, case cochée → plus de fenêtre, interrupteur la remet) ; goldens écrans 12 et 12b. Commit `feat: confirm before removing from the phone`.

### Task 3: Nombres d'écoutes fusionnés

**Files:** Modify `lib/library/db.dart` (`raisePlayCounts`, `addPlay`, `_topQuery`), `lib/library/sync.dart` · Test `test/library/plays_test.dart`, `test/library/sync_test.dart`

**Interfaces:**
- Produces : la synchro écrit `imported = max(imported, serveur)` par chemin ; `addPlay` ajoute à `count` du chemin joué ; le Top 100 et l'affichage d'un morceau fusionné utilisent `max(imported des jumeaux) + somme(count des jumeaux)`.

- [ ] Step 1: tests du point 3 de Review Focus ; Top 100 fusionné (un seul rang pour deux jumeaux) ; TopKeeper (plan 2) garde un seul jumeau.
- [ ] Step 2: échec, implémentation, verts. Commit `feat: merged play counts`.

### Task 4: Affichage Un compte / Tout / Perso et ordre des comptes

**Files:** Modify `lib/ui/phone/accounts_screen.dart`, `lib/ui/phone/home_screen.dart`, `lib/sources/accounts.dart` (ordre), `lib/l10n/strings.dart` · Test `test/ui/phone/accounts_widget_test.dart`, goldens

**Interfaces:**
- Consumes : maquette 2 écran 6 (poignée ⠿ « glisse pour l'ordre », section AFFICHAGE avec Un compte / Tout / Perso, cases à cocher des comptes, texte « Un album présent sur deux comptes… » — `strings.sameAlbumNote` existe déjà) ; maquette 1 écran 1 (puces « Tout ▾ », puis une puce par compte).
- Produces : glisser un compte change `position` (et donc la meilleure source) ; le choix du mode et des comptes est enregistré dans les réglages ; les puces de l'Accueil changent le mode (« Tout ▾ » ouvre Tout / Perso ; une puce de compte = Un compte).

- [ ] Step 1: tests d'écran (ordre glissé enregistré, mode choisi, puces) ; goldens écran 6 complet et Accueil avec puces.
- [ ] Step 2: échec, implémentation, verts ; captures simulateur montrées à Johnny. Commit `feat: account order and display mode`.

### Task 5: Playlists du serveur

**Files:** Modify `lib/sources/source.dart`, `lib/sources/subsonic.dart`, `lib/library/sync.dart`, `lib/offline/downloader.dart`, `lib/ui/phone/home_screen.dart` · Create `lib/ui/phone/playlist_screen.dart`, `lib/offline/m3u.dart` · Test `test/sources/subsonic_test.dart`, `test/library/sync_test.dart`, `test/offline/m3u_test.dart`, widget + goldens

**Interfaces:**
- Produces : `MusicSource.playlists()` → `List<SourcePlaylist{id, name, songIds}>` (Subsonic `getPlaylists` puis `getPlaylist`) ; la synchro remplit `Playlists`/`PlaylistItems` (remplacées à chaque synchro complète, gardées si la synchro échoue).
- Produces : Accueil, sous ALBUMS : section « PLAYLISTS DU SERVEUR » (nom du compte en petit en mode Tout/Perso) ; écran Playlist (comme l'écran Album : Lecture, Aléatoire, ⬇, liste dans l'ordre, doublons gardés, absents grisés) ; « Garder » une playlist = `keep` de ses morceaux + écriture de `<dossier>/Playlists/<safeName(nom)>.m3u8` (`#EXTM3U`, chemins relatifs au fichier, seulement les morceaux gardés), réécrit quand une copie arrive ou part ; retiré quand plus aucun morceau n'est gardé ; jamais de fichier m3u8 hors de `Playlists/`.

- [x] Step 1: maquette `maquettes/7-playlists.png` faite et validée par Johnny (18.11.2026) : mosaïque de 4 pochettes, nom du compte en petit (Tout / Perso), ⬇ rose si gardée ; écran Playlist = écran Album avec « PLAYLIST · <compte> », sous-titre « artiste · album » par morceau.
- [ ] Step 2: tests client (`getPlaylists`, `getPlaylist`, en-têtes), synchro (remplacement, échec garde l'ancienne), m3u8 (ordre, doublons, chemins relatifs, caractères spéciaux), point 4 de Review Focus.
- [ ] Step 3: échec, implémentation, verts ; goldens ; captures. Commit `feat: server playlists, keepable with an m3u8 file`.

### Task 6: Cover Flow couché

**Files:** Modify `lib/main.dart` (orientations), `lib/ui/phone/phone_shell.dart`, `lib/ui/coverflow_screen.dart` · Test `test/ui/phone/phone_widget_test.dart`, golden

**Interfaces:**
- Consumes : maquette 2 écran 5 (logo, pochettes en arc, titre, « Playlist · 9 morceaux · ⬇ sur l'iPhone », boutons « Lecture » / « Ouvrir la playlist », « Glisse pour défiler · touche pour jouer »).
- Produces : téléphone : portrait + paysage autorisés ; en paysage, partout sauf En cours (qui reste dessiné debout), le `PhoneShell` montre le Cover Flow plein écran sur l'album courant ; relevé → retour à l'écran d'avant. « Ouvrir la playlist » ouvre l'écran Album (les albums sont les playlists LAFLEUR, spec §2).

- [ ] Step 1: tests du point 5 de Review Focus ; golden écran 5.
- [ ] Step 2: échec, implémentation, verts ; capture simulateur couché. Commit `feat: landscape Cover Flow on phones`.

### Task 7: Tablette

**Files:** Modify `lib/main.dart`, `ios/Runner.xcodeproj` (familles iPhone + iPad), `ios/Runner/Info.plist` (orientations iPad), `lib/ui/library_screen.dart`, `lib/ui/sidebar.dart` · Test widget + goldens tablette

**Interfaces:**
- Produces : largeur ≥ 900 px → disposition en colonnes du Mac (barre de côté, liste, En cours) ; la barre de côté gagne « Comptes » (écrans 6/7) et « Sur mon iPad / Sur ma tablette » (écran du plan 2) — revient sur la règle R4 du plan 1 ; toutes orientations sur tablette.

- [ ] Step 1: tests (largeur 1024 → colonnes ; 390 → téléphone ; accès Comptes et Sur mon iPad) ; goldens iPad debout/couché.
- [ ] Step 2: échec, implémentation, verts ; capture simulateur iPad (ajouter un simulateur iPad gratuit si besoin, sans toucher au simulateur « iPhone LAFLEUR »). Commit `feat: tablet layout with the Mac columns`.

### Task 8: Essai de bout en bout et documents

**Files:** Modify `integration_test/fake_subsonic.dart` (deux faux serveurs, playlists), `.github/workflows/ci.yml`, `README.md`, `docs/conception/checklist.md` · Create `integration_test/accounts_test.dart`

- [ ] Step 1: `accounts_test.dart` : deux comptes avec le même album → une fois ; couper le premier → joue depuis le second, l'écoute part sur le second ; une playlist gardée → fichier `.m3u8` présent ; nettoyage sûr comme `mountGuarded`.
- [ ] Step 2: simulateur iPhone + job `android-emulator` ; pousser `plan-3-accounts`, CI verte.
- [ ] Step 3: README (anglais) et checklist (français). Commit `docs: plan 3 status`.
