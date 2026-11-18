# LAFLEURMUSIC pour téléphone (Android + iPhone) — spec de design

Date : 18.11.2026 · Maquettes validées : `maquettes/1-telephone-debout.png` (écrans 1 à 4) et `maquettes/2-coverflow-comptes.png` (écrans 5 à 8).
Point de départ : LAFLEURMUSIC pour ordinateur 1.0.1 (dépôt `Jonlekern/lafleurmusic-desktop`), ses specs et plans dans `docs/conception/`.
Liste de contrôle de tout ce qui a été décidé : `docs/conception/checklist.md`.

## 1. But

La même appli que sur le Mac, dans la poche : on écoute sa musique depuis ses **serveurs de musique** (Navidrome sur le NAS de Johnny,
et d'autres du même genre), et on **garde des albums sur le téléphone** pour écouter dehors, sans réseau.

**Réussi quand :**
- au premier lancement, on ajoute un compte (adresse, utilisateur, mot de passe, en-têtes HTTP si besoin), « Tester » dit si ça marche, et la bibliothèque apparaît avec les pochettes ;
- on navigue comme sur le Mac, colonnes empilées (écrans 1 à 3), et on écoute avec À suivre, aléatoire, répétition, égaliseur, fondu enchaîné, volume égal ;
- la musique continue écran éteint ; elle se pilote depuis l'écran verrouillé, la notification (Android), le Centre de contrôle (iPhone) et les écouteurs Bluetooth ;
- téléphone couché = Cover Flow (écran 5) ;
- on sélectionne des albums / playlists / morceaux → « Garder sur mon iPhone » (ou « sur mon téléphone » sous Android) ; ils deviennent de vrais fichiers dans un dossier visible, et jouent sans réseau ;
- dehors, ce qui n'est pas sur le téléphone est grisé (écran 4) ; les écoutes faites dehors arrivent sur le serveur au retour ;
- plusieurs comptes, vus un par un, tous fusionnés, ou fusion « Perso » (écran 6) ;
- l'appli tourne dans le simulateur iPhone du Mac, et l'APK Android sort de GitHub, testé sur un émulateur Android dans GitHub.

**Hors périmètre (deuxième étape) :** modifier les tags, Réparer, Supprimer / Remplacer un fichier (les serveurs ne touchent jamais aux fichiers), envoi vers le NAS (c'est à l'utilisateur), accès au NAS depuis l'extérieur (Johnny ne l'ouvre pas pour l'instant),
publication sur l'App Store / Google Play (payant, à la décision de Johnny).

**Jamais sur téléphone (décidé par Johnny) :** skins Winamp.

## 2. Ce que Johnny a dit / ce qui est supposé

| Dit par Johnny | Supposé / précisé ici |
|---|---|
| Android et iPhone, on compile sur GitHub | Une seule appli Flutter. L'APK Android est construit par GitHub Actions ; l'iPhone est construit et essayé sur le Mac (simulateur). Rien d'Android à installer sur le Mac |
| La musique : le NAS (Navidrome) et des fichiers sur le téléphone | Le téléphone parle au **serveur**, jamais aux dossiers du NAS |
| Pas que Navidrome : les applis du même genre | Famille **Subsonic** d'abord (Navidrome, Airsonic, Gonic, LMS, Funkwhale, Nextcloud Music, Ampache), puis **Jellyfin**, puis **Plex** — dans cet ordre, chacun branché sans toucher au reste |
| Aussi des en-têtes HTTP personnalisés | Par compte, autant qu'on veut ; envoyés avec **toutes** les requêtes : listes, pochettes, lecture en direct, téléchargements |
| Plusieurs comptes ; par compte, fusion, ou fusion perso | Écran 6. Même album (même artiste d'album + même nom d'album, sans accents ni casse) sur deux comptes = **une seule fois**, joué depuis la meilleure source : copie sur le téléphone, puis les comptes dans l'ordre de la liste |
| — | Une écoute est comptée sur le compte qui a joué le morceau |
| Navidrome : seulement à la maison pour l'instant | L'adresse d'un compte se change à tout moment ; rien à reconstruire le jour où il l'ouvre dehors |
| Connecter un autre serveur, télécharger des albums, et pouvoir les mettre sur son NAS | « Garder sur mon iPhone » télécharge le **fichier original** (si le serveur l'autorise, sinon la version lue en direct) ; les mettre sur le NAS = l'utilisateur, avec l'appli Fichiers |
| Pouvoir sélectionner ce qu'on garde | Écran 8 : albums, playlists, morceaux, plusieurs d'un coup, avec la place prise |
| Garde toutes tes idées | Menu façon iPod (= barre de côté du Mac), Cover Flow couché, En cours + égaliseur + À suivre, commandes écran verrouillé / Bluetooth, glisser = Lire ensuite, appui long = menu, mode molette caché, Top 100 partagé, fondu + volume égal |
| Comme la version ordi, Flutter marche partout | Mêmes couleurs, polices, composants, lecteur, file, égaliseur. Seule la **disposition** change : debout = colonnes empilées, couché = Cover Flow, tablette = colonnes côte à côte comme sur Mac |
| Nouveau dépôt | `lafleurmusic-mobile`, qui part d'une **copie** du code de l'appli Mac 1.0.1 |
| Albums + playlists | Les albums restent les playlists LAFLEUR (comme sur le Mac et la console). **En plus**, une section « Playlists du serveur » sous les albums, à l'Accueil |
| — | Top 100 gardé tout seul sur le téléphone ; limite de place 10 Go au départ, réglable |
| — | Appli en français si le téléphone est en français, sinon en anglais (comme sur Mac) |

## 3. Briques

| Rôle | Brique | Licence | Note |
|---|---|---|---|
| Lecture (fichiers et flux HTTP avec en-têtes) | `mpv_audio_kit` 0.5.1 (`Media.httpHeaders`, session multimédia iOS + notification Android) | BSD-3 | déjà là ; Android 7+ et iOS 15+ ; Flutter ≥ 3.47.4 pour iOS (installé : 3.47.7). **À prouver en tâche 1** : son, arrière-plan, écran verrouillé, en-têtes, sur simulateur iPhone et émulateur Android. Sur Mac la sortie est bloquée à 48 kHz : vérifier ce qu'il fait ici |
| Pochette de l'écran verrouillé | téléchargée par l'appli (avec les en-têtes) puis donnée en octets à la session multimédia | — | la session multimédia ne sait pas envoyer d'en-têtes |
| Serveurs | clients écrits dans l'appli avec `http` : Subsonic (jeton md5 + sel, `crypto` déjà là), Jellyfin (REST), Plex (REST + connexion par code plex.tv) | — | pas de dépendance nouvelle ; **aucun code d'Amperfy** (GPL-3, Swift) : idées seulement |
| Base | `drift` + `sqlite3` | MIT | déjà là ; schéma adapté (4.1) |
| Tags des fichiers gardés | `flutter_taglib` | déjà là | Android et iOS pris en charge ; écrit titre / artiste / album / numéro / pochette dans les fichiers téléchargés quand le serveur ne les a pas mis |
| Dossiers du téléphone | `path_provider` | BSD | iPhone : dossier Documents de l'appli, rendu visible dans Fichiers (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`). Android : `Music/LAFLEURMUSIC` (stockage partagé ; permission « audio » pour relire les fichiers posés à la main) |
| Mots de passe et jetons | `flutter_secure_storage` (Trousseau iPhone, Keystore Android) | BSD-3 | jamais en clair dans `settings.json` |
| Orientation, tactile | Flutter (`OrientationBuilder`, `Dismissible`, appui long) | BSD | rien de plus |
| Retirés de la copie du Mac | `window_manager`, `desktop_drop`, Corbeille (`trash.dart`), Winamp, Réparer, édition, `file_selector` | — | gardés dans le dépôt Mac ; retirés ici pour l'instant |

## 4. Architecture

```
lib/
  main.dart                 thème, langue, routes ; choisit la disposition (téléphone debout / couché / tablette)
  theme/                    copie du Mac (couleurs, Inter, composants LAFLEUR)
  sources/                  NOUVEAU : un « compte » = une source de musique
    source.dart             interface MusicSource : test(), sync(), streamUrl(), download(), scrobble(), coverBytes()
    subsonic.dart           famille Subsonic
    jellyfin.dart           Jellyfin (étape 2 du plan)
    plex.dart               Plex (étape 3 du plan)
    local.dart              le dossier LAFLEURMUSIC du téléphone (fichiers gardés + posés à la main)
    accounts.dart           liste ordonnée des comptes, en-têtes, mode d'affichage (un / tout / perso)
  library/                  base drift : morceaux de toutes les sources, fusion, recherche, Top 100
  offline/                  file de téléchargements, place utilisée, limite, écoutes en attente
  player/                   copie du Mac (file, À suivre, égaliseur, fondu, volume égal) ; joue un `Media` (chemin ou URL + en-têtes)
  ui/                       écrans 1 à 8 ; réutilise les widgets du Mac (track_list, now_panel, equalizer_panel, coverflow…)
  l10n/                     textes FR / EN
```

- **sources** ne connaît ni l'écran ni le lecteur. Chaque source sait lister sa musique, donner l'adresse d'un morceau (avec ses en-têtes), le télécharger, et noter une écoute.
- **library** mélange les sources selon le mode d'affichage ; l'écran ne sait jamais d'où vient un morceau.
- **player** reçoit des `Media` tout prêts (chemin local, ou URL + en-têtes) : il ne parle jamais aux serveurs.

### 4.1 Base
- `Accounts` : id, type (subsonic / jellyfin / plex), nom, adresse, utilisateur, ordre. En-têtes et mot de passe / jeton dans le stockage sécurisé, sous l'id du compte.
- `Tracks` : id, `accountId` (ou `local`), `remoteId` (id du morceau sur le serveur ; chemin pour `local`), titre, artiste, artiste d'album, album, `albumKey`, genre, numéro, disque, durée, `coverId`, taille, format, `replayGain` (si le serveur le donne).
- `Offline` : `albumKey` + `remoteId` du morceau → chemin du fichier gardé, taille, date ; marqueur « gardé par l'utilisateur » ou « gardé pour le Top 100 ».
- `PlayCounts` : clé de morceau fusionnée (`albumKey` + titre + numéro) → écoutes, dernière écoute ; rempli au départ avec les nombres d'écoutes donnés par les serveurs.
- `Playlists` : compte, `remoteId`, nom, liste ordonnée des `remoteId` de ses morceaux.
- `PendingScrobbles` : compte, `remoteId`, date ; vidé au retour du réseau.
- `Loudness` : comme sur Mac, seulement pour les fichiers gardés.

### 4.2 Synchronisation avec un serveur
- Au lancement, au retour du réseau, et quand on tire la liste vers le bas : la source donne tous ses morceaux (Subsonic : `search3` par pages, ou `getAlbumList2` + `getAlbum`), la base est mise à jour.
- Pochettes : miniatures 64 / 300 / 600 px en cache, comme sur Mac, téléchargées avec les en-têtes.
- Serveur injoignable : on garde la dernière liste connue ; ses morceaux non gardés sont grisés ; petite étiquette « Hors ligne » en haut.

### 4.3 Fusion
- Mode **Un compte** : seulement ce compte (+ ses morceaux gardés).
- Mode **Tout** / **Perso** : les comptes cochés ; deux morceaux sont « le même » s'ils ont le même `albumKey`, titre et numéro (sans accents ni casse).
- Source jouée : copie gardée sur le téléphone → sinon premier compte joignable dans l'ordre de l'écran 6.
- Les fichiers posés à la main dans le dossier LAFLEURMUSIC apparaissent toujours, quel que soit le mode.

### 4.4 Garder sur le téléphone
- Écran 8 : sélection, taille de chaque élément, place utilisée / limite ; refus clair si la limite serait dépassée.
- Téléchargement : fichier original (Subsonic `download`), sinon le flux ; un morceau à la fois, reprend au lancement suivant s'il a été coupé ; l'appli doit être ouverte (ou venir de passer en arrière-plan) — pas de téléchargement quand l'appli est fermée.
- Rangement : `LAFLEURMUSIC/Artiste/Album/NN Titre.ext` ; tags et pochette écrits si le fichier n'en a pas.
- Top 100 : les morceaux du Top 100 sont gardés tout seuls, à la maison ; ils comptent dans la limite ; un morceau qui sort du Top 100 est retiré seulement s'il a été gardé pour le Top 100.
- Retirer : appui long → « Retirer du téléphone » (le fichier est effacé du téléphone, jamais du serveur).

### 4.5 Écrans
- **Debout** (maquette 1) : Accueil (barre de côté du Mac, choix du compte, recherche, Bibliothèque, Sur mon iPhone, Albums) → Album / Artiste / Genre / Morceaux / Top 100 → En cours (onglets À suivre / Égaliseur / Lecture). Mini-lecteur en bas. Glisser depuis le bord gauche = retour.
- Glisser un morceau vers la gauche = **Lire ensuite** ; appui long = menu (Lire ensuite, Ajouter à la file, Garder sur mon iPhone / Retirer du téléphone, Sélectionner…).
- **Couché** (maquette 2, écran 5) : Cover Flow plein écran ; glisser pour défiler, toucher la pochette du milieu = Lecture. Pas de Cover Flow couché sur l'écran En cours.
- **Tablette** (largeur ≥ 900 px) : la disposition en colonnes du Mac.
- **Réglages → Comptes** (écrans 6 et 7) et **Sur mon iPhone** (écran 8).
- **Mode molette caché** : une molette cliquable d'iPod tactile en bas de l'écran. **Maquette à faire et à valider par Johnny avant sa tâche** (déclencheur et dessin pas encore décidés).

### 4.6 Lecture
- Copie du lecteur du Mac. Les flux HTTP reçoivent les en-têtes du compte par `Media.httpHeaders`.
- Arrière-plan : iPhone `UIBackgroundModes: audio` ; Android service de premier plan de `mpv_audio_kit`.
- Volume égal : ReplayGain donné par le serveur s'il y en a ; mesure EBU R128 seulement sur les fichiers gardés ; sinon pas de correction.
- Écoute comptée (« moitié ou 4 min », règle du Mac) → `scrobble` du compte qui joue, ou `PendingScrobbles` hors ligne.

## 5. Erreurs
- « Tester » échoue : message simple (adresse injoignable / mauvais mot de passe / en-tête refusé par le proxy).
- Serveur perdu pendant la lecture : le morceau en cours finit s'il est en mémoire, puis on saute au prochain morceau gardé ; message « Hors ligne ».
- Téléchargement refusé ou coupé : repris plus tard ; après 3 échecs, marqué en rouge dans « Sur mon iPhone ».
- Place pleine : refus avant de commencer, avec la place qu'il faudrait.
- Format illisible : morceau sauté, comme sur Mac.

## 6. Tests
- Tests Dart : client Subsonic (réponses enregistrées, jeton, en-têtes partout), fusion (même album sur deux comptes, ordre, hors ligne), file de téléchargements (reprise, limite, Top 100), écoutes en attente, base (schéma).
- Tests d'écrans : goldens des écrans 1 à 8 comparés aux maquettes ; orientation debout / couché / tablette.
- Serveur d'essai : un Navidrome dans Docker (GitHub Actions) avec des fichiers d'exemple **libres de droits** ; jamais la vraie bibliothèque de Johnny.
- GitHub Actions : `flutter test`, construction de l'APK, tests d'intégration sur un émulateur Android.
- Sur le Mac : construction iPhone et tests d'intégration dans le simulateur ; captures d'écran montrées à Johnny.
- Essai réel sur le téléphone de Johnny avec son Navidrome à la maison : par lui, quand il le veut.

## 7. Prérequis
- Simulateur iPhone : aucun simulateur iPhone n'a été trouvé sur le Mac ; il faudra en ajouter un dans Xcode (gratuit) — à vérifier en tâche 1.
- Dépôt GitHub `Jonlekern/lafleurmusic-mobile` : Johnny a dit oui pour le créer **dès le début** (pour construire et tester Android à chaque étape). Créé **privé** (choix de Claude : on peut le rendre public plus tard, l'inverse non) ; chaque envoi reste demandé à Johnny avant. Commits en anglais, auteur `Jonlekern <288344322+Jonlekern@users.noreply.github.com>`, sans mention d'IA.
- Installer sur un vrai iPhone sans compte Apple payant : possible depuis Xcode, valable 7 jours. Comptes Apple / Google Play payants : décision de Johnny.

## 8. Choix faits pendant la relecture (à vérifier par Johnny)
- **Jellyfin et Plex font partie de ce projet**, après la famille Subsonic, chacun dans sa propre partie du plan ; la première version qu'on peut essayer marche avec Subsonic seulement.
- **Si `mpv_audio_kit` échoue en tâche 1** sur iPhone ou Android (son, arrière-plan, écran verrouillé, en-têtes) : plan B `just_audio` + `audio_service` sur ce téléphone, sans égaliseur ni fondu au départ. Je le dis à Johnny avant de continuer.
- **« À la maison »** = le serveur répond **et** le téléphone est en Wi-Fi. Les téléchargements automatiques (Top 100) se font seulement là, jamais en données mobiles ; ceux que Johnny lance lui-même partent tout de suite.
- **Nombres d'écoutes** : au départ, pour un morceau présent sur deux comptes, on garde le plus grand des deux ; ensuite chaque écoute s'ajoute. « Top 100 partagé » = partagé par les serveurs ; l'appli Mac ne lit pas encore les serveurs (plus tard, hors de ce projet).
- **Fichiers posés à la main** dans `Music/LAFLEURMUSIC` (Android) : lus seulement ; l'appli n'efface et ne modifie que les fichiers qu'elle a téléchargés elle-même.
- **Playlists du serveur** (réponse de Johnny : albums + playlists) : lues sur chaque compte (Subsonic `getPlaylists` / `getPlaylist`), affichées sous les albums à l'Accueil. Elles ne sont jamais fusionnées entre comptes : en mode Tout / Perso, chacune porte le nom de son compte en petit. Lecture seule sur téléphone (les modifier = deuxième étape). Garder une playlist = garder ses morceaux (rangés Artiste/Album comme les autres) + un fichier `LAFLEURMUSIC/Playlists/Nom.m3u8` qui donne l'ordre.
- **Limite de place** : 10 Go au départ, réglable de 1 Go à toute la place libre. Quand elle est atteinte, le Top 100 automatique s'arrête ; ce que Johnny a gardé lui-même n'est jamais retiré tout seul.
- **Dossier choisi par l'utilisateur** (Johnny, 18.11.2026 : « il peut aussi sélectionner l'endroit du dossier ; dans le cloud c'est aussi OK ») : par défaut `LAFLEURMUSIC` (iPhone : Fichiers → Sur mon iPhone ; Android : `Music/LAFLEURMUSIC`). Dans « Sur mon iPhone », « Choisir le dossier… » ouvre le sélecteur du système. iPhone : n'importe quel dossier de Fichiers, **iCloud Drive compris** (accès gardé par un signet de sécurité). Android : un dossier du téléphone ou de la carte SD ; un dossier cloud seulement s'il existe comme vrai dossier (appli de synchro) — Google Drive n'en donne pas. Changer de dossier **déplace** les morceaux déjà gardés vers le nouveau (copie puis effacement), avec la place nécessaire vérifiée avant. Un fichier dans le cloud que le système a retiré du téléphone (iCloud « Optimiser le stockage ») se télécharge quand on le joue : il faut alors du réseau. La limite reste choisie par l'utilisateur (1 Go → toute la place libre).
- **Mode clair** (Johnny, 18.11.2026) : l'affichage actuel s'appelle **mode sombre**. Un **mode clair** s'ajoute : fond blanc, logo écrit en noir, détails en rose `#F26EF2`. Plan à part (plan 7), **maquette d'abord, validée par Johnny** ; il suit **automatiquement** le réglage du téléphone (clair / sombre), sans choix dans l'appli (réponse de Johnny : 1).
