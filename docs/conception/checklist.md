# LAFLEURMUSIC mobile — liste de contrôle

Mise à jour : 18.11.2026. ✅ = décidé avec Johnny · ⬜ = encore à décider ou à faire.

## Étapes
- ✅ Idées (brainstorm)
- ✅ Écrans : reprendre ceux du Mac, empilés
- ✅ Maquettes 1 et 2 validées (la molette aura sa propre maquette)
- ✅ Spec écrite et validée (18.11.2026)
- ✅ Plan 1 « écouter son serveur » et plan 2 « hors ligne » écrits et codés ; plans 3 à 7 ensuite
- ⬜ Code (plans 1 et 2 faits, essai de bout en bout dans le simulateur ; l'écran « Sur mon iPhone » attend la maquette)
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

## Ordre de construction
- ✅ Famille Subsonic, puis Jellyfin, puis Plex : tous dans ce projet, l'un après l'autre

## Garder sur le téléphone
- ✅ « Garder sur mon iPhone / téléphone » par sélection : album, playlist, morceaux, plusieurs d'un coup
- ✅ Vrais fichiers dans un dossier visible : Fichiers → Sur mon iPhone → LAFLEURMUSIC ; Android : Musique/LAFLEURMUSIC
- ✅ Rangés Artiste/Album, avec tags et pochette ; fichier original si le serveur le permet
- ✅ Les fichiers posés à la main dans ce dossier apparaissent dans l'appli
- ✅ Dossier au choix (iCloud Drive compris) ; le déplacer emporte les copies
- ✅ Les mettre sur le NAS : c'est à l'utilisateur (appli Fichiers) ; l'appli n'écrit jamais sur le NAS
- ✅ Top 100 gardé tout seul
- ✅ Les écoutes faites dehors sont envoyées au serveur au retour
- ✅ Limite de place : 10 Go au départ, réglable (choix de Claude, à vérifier) ; la file refuse ce qui dépasse la limite ou la place libre
- ✅ Plan 2 essayé de bout en bout (faux serveur coupé puis rétabli) : copie dans le dossier, lecture sans serveur, morceau non gardé grisé, écoute envoyée au retour
- ⬜ Écran « Sur mon iPhone » (limite, dossier, Top 100) : après la maquette validée par Johnny

## Écrans et tactile (idées gardées)
- ✅ Menu façon iPod : Musique → Artistes / Albums (= playlists) / Morceaux / Top 100
- ✅ Téléphone à l'horizontale = Cover Flow
- ✅ En cours : grosse pochette, égaliseur, À suivre
- ✅ Commandes sur l'écran verrouillé, dans les notifications et sur les écouteurs Bluetooth
- ✅ Glisser vers la gauche = Lire ensuite ; appui long = menu
- ✅ Mode caché : molette d'iPod tactile
- ✅ Fondu enchaîné et Volume égal
- ✅ Playlists = albums, comme sur le Mac et la console
- ✅ En plus : section « Playlists du serveur » sous les albums (lecture seule, gardables)

## Mode clair
- ✅ L'affichage actuel = mode sombre
- ✅ Mode clair : fond blanc, logo en noir, détails rose
- ⬜ Maquette du mode clair (plan 7), à valider par Johnny
- ✅ Automatique : suit le réglage clair / sombre du téléphone

## Jamais sur téléphone
- ✅ Skins Winamp (pas besoin, dit Johnny)

## Deuxième étape (plus tard)
- ⬜ Modifier les tags et Réparer (les serveurs ne modifient pas les fichiers)

## À vérifier pendant le code
- ⬜ mpv_audio_kit sur iPhone et Android (sur Mac, le son est bloqué à 48 kHz : vérifier ici)
- ⬜ Pochette de l'écran verrouillé avec des en-têtes : l'appli la télécharge elle-même
- ⬜ Licences : Amperfy = idées seulement, pas de code (GPL-3)
