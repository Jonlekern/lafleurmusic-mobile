# LAFLEURMUSIC mobile — liste de contrôle

Mise à jour : 19.11.2026. ✅ = décidé avec Johnny · ⬜ = encore à décider ou à faire.

## Étapes
- ✅ Idées (brainstorm)
- ✅ Écrans : reprendre ceux du Mac, empilés
- ✅ Maquettes 1 et 2 validées (la molette aura sa propre maquette)
- ✅ Spec écrite et validée (18.11.2026)
- ✅ Plans 1 « écouter son serveur », 2 « hors ligne », 3 « plusieurs comptes », 4 « Jellyfin » et 5 « Plex » écrits et codés ; plan 8 « file et bibliothèque » codé ; plans 6, 7 et 9 ensuite
- ⬜ Code (plans 1, 2, 3, 4, 5 et 8 faits, essais de bout en bout dans le simulateur ; l'écran « Sur mon iPhone » attend la maquette)
- ⬜ Essais : simulateur iPhone sur le Mac, Android construit par GitHub
- ✅ Dépôt GitHub créé dès le début (privé au départ) ; accord de Johnny avant chaque envoi

## Téléphones
- ✅ Une seule appli Flutter pour Android et iPhone, à partir de l'appli Mac 1.0.1
- ✅ Android : l'APK est construit par GitHub (rien à installer sur le Mac)
- ✅ iPhone : essais dans le simulateur. Sans compte Apple payant, une installation sur un vrai iPhone dure 7 jours
- ✅ Nouveau dépôt `lafleurmusic-mobile`, qui part d'une copie du code de l'appli Mac
- ✅ Disposition : comme la version ordi ; téléphone debout = colonnes du Mac l'une après l'autre, couché = Cover Flow, tablette = colonnes côte à côte

## D'où vient la musique
- ✅ Des serveurs de musique, pas les dossiers du NAS
- ✅ Famille Subsonic d'abord (Navidrome, Airsonic, Gonic, LMS, Funkwhale, Nextcloud Music, Ampache), puis Jellyfin, puis Plex
- ✅ Plex : connexion par un code validé par Johnny sur plex.tv
- ✅ En-têtes HTTP personnalisés par compte (pour tout : listes, pochettes, lecture, téléchargements)
- ✅ Plusieurs comptes ; vue par compte, tout fusionné, ou fusion choisie
- ✅ Même album sur deux comptes : affiché une fois, joué depuis la meilleure source (copie sur le téléphone, puis les comptes dans l'ordre choisi)
- ✅ L'écoute est comptée sur le compte qui a joué le morceau
- ✅ Navidrome seulement à la maison pour l'instant ; l'adresse du serveur peut changer plus tard
- ✅ Dehors : seulement la musique gardée sur le téléphone, le reste est grisé
- ✅ Plan 3 fait : deux comptes fusionnés (affichage « Un compte », « Tous » ou « Choisis »), albums et morceaux en double affichés une fois, écoutes et nombres d'écoutes fusionnés
- ✅ Plan 3 essayé de bout en bout (deux faux serveurs) : album affiché une fois, premier serveur coupé → lecture depuis le second et écoute envoyée au second, playlist gardée → fichier `.m3u8` dans `Playlists/`
- ✅ Plan 4 fait : comptes Jellyfin (nom et mot de passe ; l'appli garde la clé de connexion et se reconnecte seule si le serveur l'oublie), bibliothèque, pochettes, playlists, lecture, copies sur le téléphone, écoutes envoyées
- ✅ Plan 4 essayé : contre un vrai Jellyfin dans GitHub (sons d'essai faits par nous), et de bout en bout avec un faux Navidrome et un faux Jellyfin qui ont le même album → affiché une fois, Navidrome coupé → lecture depuis Jellyfin et écoute envoyée à Jellyfin
- ✅ Plan 5 fait : comptes Plex (un code tapé sur plex.tv/link, pas de mot de passe ; l'appli retrouve seule la meilleure adresse du serveur et dit « À reconnecter » si Plex refuse la clé), bibliothèque, pochettes, playlists, lecture, copies sur le téléphone, écoutes envoyées (Plex ne prend pas la date : une écoute faite hors ligne compte le jour où elle part)
- ✅ Plan 5 essayé de bout en bout avec un faux plex.tv et un faux serveur Plex (jamais un vrai compte Plex) : compte ajouté par le code, album affiché une fois avec les trois autres comptes, les autres coupés → lecture depuis Plex et écoute envoyée à Plex, un morceau gardé sur le téléphone

## Ordre de construction
- ✅ Famille Subsonic, puis Jellyfin, puis Plex : tous dans ce projet, l'un après l'autre (Subsonic, Jellyfin et Plex faits)

## Garder sur le téléphone
- ✅ « Garder sur mon iPhone / téléphone » par sélection : album, playlist, morceaux, plusieurs d'un coup
- ✅ Vrais fichiers dans un dossier visible : Fichiers → Sur mon iPhone → LAFLEURMUSIC ; Android : Musique/LAFLEURMUSIC
- ✅ Rangés Artiste/Album, avec tags et pochette ; fichier original si le serveur le permet
- ✅ Les fichiers posés à la main dans ce dossier apparaissent dans l'appli
- ⬜ Dossier au choix (iCloud Drive compris) ; le déplacer emporte les copies : moteur fait, écran à venir
- ✅ Les mettre sur le NAS : c'est à l'utilisateur (appli Fichiers) ; l'appli n'écrit jamais sur le NAS
- ✅ Top 100 gardé tout seul
- ✅ Les écoutes faites dehors sont envoyées au serveur au retour
- ⬜ Limite de place : 10 Go au départ, réglable (choix de Claude, à vérifier) : moteur fait (la file refuse ce qui dépasse la limite ou la place libre), écran à venir
- ✅ Plan 2 essayé de bout en bout (faux serveur coupé puis rétabli) : copie dans le dossier, lecture sans serveur, morceau non gardé grisé, écoute envoyée au retour
- ⬜ Écran « Sur mon iPhone » (limite, dossier, Top 100) : après la maquette validée par Johnny

## Écrans et tactile (idées gardées)
- ✅ Menu façon iPod : Musique → Artistes / Albums (= playlists) / Morceaux / Top 100
- ✅ Téléphone à l'horizontale = Cover Flow
- ✅ En cours : grosse pochette, égaliseur, À suivre
- ✅ Commandes sur l'écran verrouillé, dans les notifications et sur les écouteurs Bluetooth
- ✅ Glisser vers la gauche = Lire ensuite ; appui long = menu
- ✅ Mode Classic (molette d'iPod, version A de la maquette 6) ou Mode normal, au choix dans Réglages
- ✅ Fondu enchaîné et Volume égal
- ✅ Playlists = albums, comme sur le Mac et la console
- ✅ En plus : section « Playlists du serveur » sous les albums (lecture seule, gardables) ; garder une playlist écrit un fichier `.m3u8` dans `Playlists/` (l'appli n'efface que ses propres fichiers)
- ✅ Plan 3 fait : Cover Flow en couché (comptes et playlists compris), tablette = colonnes côte à côte
- ✅ Plan 3 : visuels de la tablette, texte « Ouvrir l'album » du Cover Flow et texte « Morceau absent » validés par Johnny (19.11.2026)
- ✅ Plan 8 fait : glisser vers la droite = Ajouter à la file (bulle « Ajouté à la file » avec Annuler et Voir la file) ; « Vider » ne retire que tes ajouts, après confirmation, la suite de l'album reste
- ✅ Plan 8 fait : écran Albums (touche le titre ALBUMS de l'Accueil) avec « Écoutés récemment » et le tri Nom, Artiste, Ajout récent, Plus écouté, gardé dans les réglages ; « Aller à l'album » et « Aller à l'artiste » dans le menu ⋯ de En cours
- ✅ Plan 8 essayé de bout en bout dans le simulateur, avec des fichiers posés à la main (le premier compte demandé vient d'un faux serveur) : glisser, bulle, Annuler, Vider, Aller à l'album, tri gardé

## Mode clair
- ✅ L'affichage actuel = mode sombre
- ✅ Mode clair : fond blanc, logo en noir, détails rose
- ✅ Maquette du mode clair validée (`maquettes/5-mode-clair.png`, 18.11.2026)
- ✅ Automatique : suit le réglage clair / sombre du téléphone

## Icône
- ✅ Jour : fond blanc, fleur noire · Nuit : fond noir, fleur rose (`maquettes/8-icones.png`)

## Jamais sur téléphone
- ✅ Skins Winamp (pas besoin, dit Johnny)

## Deuxième étape (plus tard)
- ⬜ Modifier les tags et Réparer (les serveurs ne modifient pas les fichiers)

## À vérifier pendant le code
- ⬜ mpv_audio_kit sur iPhone et Android (sur Mac, le son est bloqué à 48 kHz : vérifier ici)
- ⬜ Pochette de l'écran verrouillé avec des en-têtes : l'appli la télécharge elle-même
- ⬜ Licences : Amperfy = idées seulement, pas de code (GPL-3)
