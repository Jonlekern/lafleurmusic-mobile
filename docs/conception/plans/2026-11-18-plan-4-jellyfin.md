# LAFLEURMUSIC téléphone — plan 4 « Jellyfin » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un compte Jellyfin marche comme un compte Subsonic : Tester, bibliothèque, pochettes, lecture en direct, garder sur le téléphone, écoutes envoyées, playlists — sans rien changer pour l'utilisateur à part « Jellyfin » dans le choix du type de serveur (écran 7).

**Architecture:** `lib/sources/jellyfin.dart` implémente `MusicSource` (le même contrat que `SubsonicSource`, plans 1-3). Les clés de morceau deviennent génériques : `<type>://<compte>/<id>` (`subsonic://`, `jellyfin://`) ; `parseRemoteKey` reconnaît les deux. Le reste (synchro, fusion, file de téléchargements, écoutes en attente) ne change pas.

**Tech Stack:** `http` (+ `MockClient`), API REST Jellyfin 10.9+, Docker `jellyfin/jellyfin` dans GitHub Actions pour l'essai réel.

**Spec:** `docs/conception/specs/2026-11-18-lafleurmusic-mobile-design.md` §2 (famille Subsonic, puis Jellyfin), §3, §4 · Maquette : `maquettes/2-coverflow-comptes.png` écran 7 (onglet « Jellyfin »).

## Global Constraints

- Aucun nouveau visuel : l'onglet « Jellyfin » de l'écran 7 existe déjà dans la maquette validée.
- Les en-têtes HTTP du compte partent avec **toutes** les requêtes. Le jeton Jellyfin (`X-Emby-Token` / `Authorization: MediaBrowser … Token="…"`) et le mot de passe : jamais dans un journal ni un message d'erreur ; jeton dans `flutter_secure_storage`, jamais le mot de passe une fois le jeton obtenu.
- Mêmes règles que les plans 1-3 : R3 (un serveur qui répond 0 album n'efface rien), délais 8 s / 15 s, Tester → mêmes messages (injoignable / mauvais mot de passe / en-tête refusé / certificat refusé / pas un serveur Jellyfin).
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-4-jellyfin`, envoi libre sur cette branche.
- Jamais le vrai serveur de Johnny dans les tests.

## Review Focus

1. **Jeton expiré ou révoqué** (401 après des semaines) : l'appli se reconnecte une fois avec le mot de passe enregistré, sinon « mauvais mot de passe » — test en tâche 1.
2. **Bibliothèque sans « Music »** ou plusieurs bibliothèques musicales : toutes les bibliothèques de type musique sont lues — test en tâche 2.
3. **Morceau sans album** (single isolé) : rangé sous « Album inconnu » de son artiste, jamais perdu — test en tâche 2.
4. **Fichier original refusé** (droits de téléchargement retirés à l'utilisateur) : repli sur le flux, comme Subsonic — test en tâche 3.
5. **Écoute hors ligne** envoyée au retour avec la date d'origine — test en tâche 3.

---

### Task 1: Connexion Jellyfin et Tester

**Files:** Create `lib/sources/jellyfin.dart` · Modify `lib/sources/accounts.dart` (`AccountType.jellyfin`), `lib/sources/account_service.dart`, `lib/ui/phone/account_form.dart` (l'onglet Jellyfin devient actif), `lib/player/media_resolver.dart` (`parseRemoteKey` générique) · Test `test/sources/jellyfin_test.dart`

**Interfaces:**
- Produces : `JellyfinSource(account, password, headers, {client})` : `test()` = `GET /System/Info/Public` (reconnaît Jellyfin) puis `POST /Users/AuthenticateByName` (→ `AccessToken`, `User.Id`, rangés dans le coffre sous l'id du compte) ; `Authorization: MediaBrowser Client="LAFLEURMUSIC", Device="<iPhone|Android>", DeviceId="<id stable>", Version="<version>", Token="…"` sur toutes les requêtes suivantes. 401 → une nouvelle authentification, puis `wrongPassword`.
- Produces : `parseRemoteKey(path)` → `(type, accountId, id)?` pour `subsonic://` et `jellyfin://`.

- [ ] Step 1: tests (Tester ok / 401 / proxy 403 sans en-tête / pas Jellyfin / jeton gardé / point 1 de Review Focus). Échec, implémentation, verts. Commit `feat: Jellyfin sign-in and server test`.

### Task 2: Bibliothèque Jellyfin

**Files:** Modify `lib/sources/jellyfin.dart`, `lib/library/sync.dart` (si besoin) · Test `test/sources/jellyfin_test.dart`, `test/library/sync_test.dart`

**Interfaces:**
- Produces : `albums()` = `GET /Users/{u}/Items?IncludeItemTypes=MusicAlbum&Recursive=true&StartIndex=…&Limit=500&Fields=…` sur chaque vue de type `music` ; `albumSongs(id)` = `GET /Users/{u}/Items?ParentId={id}&IncludeItemTypes=Audio&SortBy=ParentIndexNumber,IndexNumber` ; `SourceSong` rempli (titre, artistes, artiste d'album, piste, disque, durée `RunTimeTicks/10000`, taille et format de `MediaSources[0]`, `NormalizationGain` → `replayGainTrack`, `UserData.PlayCount`) ; `coverUri(id, size)` = `/Items/{id}/Images/Primary?maxWidth=size&quality=90` ; `playlists()` = `/Users/{u}/Items?IncludeItemTypes=Playlist` puis `/Playlists/{id}/Items`.

- [ ] Step 1: tests sur réponses enregistrées (pages, points 2-3 de Review Focus, playlists, pochettes avec en-têtes). Échec, implémentation, verts. Commit `feat: Jellyfin library, covers and playlists`.

### Task 3: Lecture, téléchargement, écoutes

**Files:** Modify `lib/sources/jellyfin.dart` · Test `test/sources/jellyfin_test.dart`, `test/offline/downloader_test.dart`

**Interfaces:**
- Produces : `streamUri(id)` = `/Audio/{id}/universal?UserId=…&Container=flac,mp3,m4a,ogg,opus,wav&TranscodingContainer=mp3&AudioCodec=mp3&api_key=…` (le jeton est aussi dans l'en-tête ; jamais affiché) ; `downloadUri(id)` = `/Items/{id}/Download` ; `scrobble(id, at)` = `POST /Users/{u}/PlayedItems/{id}?DatePlayed=<ISO date d'origine>` ; même classement des erreurs que Subsonic (P7b du plan 2 : 404 = refus du morceau, le reste arrête la file).

- [ ] Step 1: tests (flux avec en-têtes, téléchargement + repli, écoute avec date d'origine, points 4-5). Échec, implémentation, verts. Commit `feat: Jellyfin playback, downloads and scrobbles`.

### Task 4: Essai réel et bout en bout

**Files:** Create `tool/jellyfin-ci.sh`, `test/sources/jellyfin_contract_test.dart`, `integration_test/fake_jellyfin.dart` · Modify `.github/workflows/ci.yml` (job `jellyfin`), `integration_test/accounts_test.dart`, `README.md`, `docs/conception/checklist.md`

- [ ] Step 1: job CI : `jellyfin/jellyfin` (version fixée), assistant de démarrage par l'API (utilisateur + bibliothèque musique sur des sons d'essai libres de droits générés), contrat : Tester, albums, morceaux, flux, téléchargement, écoute.
- [ ] Step 2: bout en bout : un compte Navidrome (faux) + un compte Jellyfin (faux) avec le même album → une fois, meilleure source, écoute sur le bon compte ; simulateur iPhone + job Android.
- [ ] Step 3: CI verte, README et checklist. Commit `docs: plan 4 Jellyfin status`.
