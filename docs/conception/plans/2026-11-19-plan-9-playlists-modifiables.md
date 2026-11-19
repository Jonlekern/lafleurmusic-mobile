# LAFLEURMUSIC téléphone — plan 9 « playlists modifiables » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** créer, renommer, remplir, réordonner et supprimer des playlists depuis le téléphone (n° 6, 7, 8 du comparatif Spotify), **avec ou sans serveur** : une playlist peut vivre seulement sur le téléphone, ou être rangée sur un serveur (Navidrome, Jellyfin, Plex).

**Architecture:** une nouvelle sorte de playlist, « sur le téléphone » (`PhonePlaylists` + `PhonePlaylistItems` en base, schéma v5), à côté des playlists des serveurs (plan 3, tables `Playlists` / `PlaylistItems`). Un `PlaylistStore` unique offre les mêmes actions aux deux sortes ; pour une playlist de serveur, chaque action appelle le serveur puis relit la playlist (le serveur fait foi) ; pour une playlist du téléphone, tout reste en local. Les morceaux sont désignés par leur clé (`subsonic://…`, `jellyfin://…`, `plex://…` ou chemin local).

**Tech Stack:** drift (migration v5), API Subsonic `createPlaylist` / `updatePlaylist` / `deletePlaylist`, Jellyfin `POST /Playlists`, `POST/DELETE /Playlists/{id}/Items`, `POST /Playlists/{id}/Items/{item}/Move/{index}`, Plex `POST /playlists`, `PUT /playlists/{id}/items`, `DELETE /playlists/{id}/items/{item}`, `PUT …/move`.

**Spec:** spec §8 (plan 9) · Recherche : `docs/conception/recherche/spotify-playlists-file.md` · Maquette validée : `maquettes/15-playlists-modifiables.png` (écrans A à E, version 3 « inspirée de Spotify », oui de Johnny le 19.11.2026).

## Global Constraints

- Visuel : exactement la maquette 15.
  - A : « + » à côté du titre dans En cours ; dans les listes, menu ⋯ → « Ajouter à une playlist ».
  - B : feuille « Ajouter à une playlist », bouton « Nouvelle playlist », recherche, cases à cocher (plusieurs), « OK » ; bulle « Ajouté à N playlists ».
  - C : plein écran « Donne un nom à ta playlist », « Où la ranger : » **Sur mon iPhone** (Android : « Sur mon téléphone ») / un bouton par compte qui sait écrire des playlists ; cette ligne est cachée quand il n'y a aucun compte.
  - D : boutons « Ajouter » (recherche dans ta musique), « Modifier », « Trier », lecture ; doublon : « Déjà dans « Nom » » / « Ignorer » (par défaut) · « Ajouter quand même » ; pour plusieurs morceaux : « N morceaux sur M sont déjà dedans ».
  - E : « Modifier » : nom, pochette, retirer (−), déplacer (≡), « Supprimer la playlist » avec confirmation.
- **Sans serveur, tout marche** (Johnny, 19.11.2026 : « pas tous les utilisateurs ont un serveur et un Mac ») : une playlist du téléphone peut contenir des fichiers locaux et des morceaux de serveur ; rien ne suppose un serveur ou un Mac dans les textes.
- Une playlist du téléphone n'est jamais envoyée sur un serveur sans action de l'utilisateur ; une playlist de serveur n'est jamais copiée en local sans « Garder ».
- « Garder » une playlist du téléphone = garder ses morceaux + un `.m3u8` sous `<racine>/Playlists/`, avec les mêmes règles que le plan 3 (seuls les fichiers notés par l'appli sont effacés).
- Pochette : une image choisie dans les photos du téléphone, gardée dans le dossier de l'appli (playlists du téléphone) ; pour un serveur, seulement si son API le permet, sinon le choix de pochette est caché.
- Un serveur qui refuse l'écriture (droits, ancienne version) : message clair, rien de changé en local, et ce compte n'est plus proposé dans « Où la ranger ».
- Mêmes textes en anglais. Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-9-playlists`.

## Review Focus

1. **Ajouter le même morceau à 3 playlists dont une le contient déjà** : une seule question pour celle-là, les deux autres reçoivent l'ajout — test en tâche 3.
2. **Serveur injoignable pendant un ajout** à une playlist de serveur : message, rien d'ajouté en local, rien de perdu ; on peut réessayer — test en tâche 2.
3. **Playlist du téléphone avec un morceau de serveur dont le compte est supprimé** : la ligne reste, grisée « Morceau absent », comme au plan 3 ; jamais d'effacement silencieux — test en tâche 1.
4. **Réordonner vite plusieurs fois** une playlist de serveur : l'ordre final est le bon (actions mises en file, une à la fois) — test en tâche 2.
5. **Mise à jour depuis 0.x** (schéma v4 → v5) : rien de perdu, migration dans une transaction — test en tâche 1.

---

### Task 1: Playlists du téléphone (base et magasin)

**Files:** Modify `lib/library/db.dart` (v5 : `PhonePlaylists`, `PhonePlaylistItems`), `lib/library/library_view.dart` · Create `lib/library/playlist_store.dart` · Test `test/library/playlist_store_test.dart`, `test/library/db_migration_test.dart`

**Interfaces:**
- Produces : `PlaylistRef` (`phone(id)` ou `server(accountId, remoteId)`) ; `PlaylistStore.create(name, {String? accountId}) → PlaylistRef`, `add(ref, List<String> keys, {bool allowDuplicates})`, `duplicatesIn(ref, keys) → List<String>`, `remove(ref, List<int> positions)`, `move(ref, from, to)`, `rename(ref, name)`, `delete(ref)`, `setCover(ref, File)` ; les playlists du téléphone apparaissent avec celles des serveurs à l'Accueil.

- [ ] Step 1: tests (créer / ajouter / doublons / retirer / déplacer / renommer / supprimer sans aucun compte, points 3 et 5). Échec, implémentation, verts. Commit `feat: playlists on the phone`.

### Task 2: Écrire sur les serveurs

**Files:** Modify `lib/sources/source.dart` (`PlaylistWriter` optionnel), `lib/sources/subsonic.dart`, `lib/sources/jellyfin.dart`, `lib/sources/plex.dart`, `lib/library/playlist_store.dart` · Test `test/sources/*_test.dart`, `test/library/playlist_store_test.dart`

**Interfaces:**
- Produces : `PlaylistWriter.createPlaylist(name) → remoteId`, `addToPlaylist(id, songIds)`, `removeFromPlaylist(id, positions)`, `movePlaylistItem(id, from, to)` (Subsonic : réécrit la liste par `createPlaylist?playlistId=` si besoin), `renamePlaylist`, `deletePlaylist` ; un compte sans écriture n'implémente pas `PlaylistWriter`.

- [ ] Step 1: tests sur réponses enregistrées pour les trois serveurs (points 2 et 4, refus d'écriture). Échec, implémentation, verts. Commit `feat: edit server playlists`.

### Task 3: Ajouter à une playlist (écrans A, B, C, doublons)

**Files:** Create `lib/ui/phone/add_to_playlist_sheet.dart`, `lib/ui/phone/new_playlist_screen.dart` · Modify `lib/ui/phone/now_screen.dart` (« + »), `lib/ui/track_menu.dart`, `lib/l10n/strings.dart` · Test widget, goldens (A, B, C)

- [ ] Step 1: tests (plusieurs cases, nouvelle playlist puis cochée, « Où la ranger » caché sans compte, doublons avec « Ignorer » par défaut, point 1). Échec, implémentation, verts. Commit `feat: add to several playlists at once`.

### Task 4: La playlist : Ajouter, Modifier, Trier (écrans D, E)

**Files:** Modify `lib/ui/phone/playlist_screen.dart` · Create `lib/ui/phone/playlist_edit_screen.dart` · Test widget, goldens (D, E)

- [ ] Step 1: tests (recherche dans ta musique, retirer, déplacer, renommer, pochette, supprimer avec confirmation, garder / ne plus garder une playlist du téléphone → `.m3u8`). Échec, implémentation, verts. Commit `feat: edit, sort and delete a playlist`.

### Task 5: Bout en bout et documents

**Files:** Modify `integration_test/accounts_test.dart` (ou nouveau), faux serveurs (écriture de playlists), `README.md`, `docs/conception/checklist.md`

- [ ] Step 1: bout en bout sur le simulateur iPhone : sans compte (playlist du téléphone, garder → `.m3u8`), puis avec un faux Navidrome (créer sur le serveur, ajouter, réordonner, relire) ; job Android ; CI verte.
- [ ] Step 2: README (anglais) et checklist (français). Commit `docs: plan 9 status`.
