import 'package:flutter/widgets.dart';

import '../sources/account_service.dart';
import '../sources/accounts.dart';
import '../sources/source.dart';

/// Textes FR / EN : français si la langue du système commence par « fr », sinon anglais.
class Strings {
  const Strings._(this.fr);
  final bool fr;

  static Strings of(Locale locale) => Strings._(locale.languageCode == 'fr');

  String _t(String f, String e) => fr ? f : e;

  String get whereIsMusic => _t('Où est ta musique ?', 'Where is your music?');
  String get organizesAlone => _t(
    'LAFLEURMUSIC range tout seul tes albums, artistes et pochettes.',
    'LAFLEURMUSIC sorts your albums, artists and covers by itself.',
  );
  String get dropFolderHere =>
      _t('Glisse ton dossier de musique ici', 'Drop your music folder here');
  String get folderOrNas => _t(
    "un dossier sur l'ordi, ou ton NAS s'il est connecté",
    'a folder on this computer, or your NAS if it is connected',
  );
  String get chooseFolder => _t('Choisir un dossier…', 'Choose a folder…');
  String get useMusicFolder =>
      _t('Utiliser mon dossier Musique', 'Use my Music folder');
  String get nasHint => _t(
    "Un NAS ? Connecte-le d'abord dans le Finder (ou l'Explorateur sous Windows), puis choisis son dossier.",
    'A NAS? Connect it in Finder (or File Explorer on Windows) first, then choose its folder.',
  );
  String get library => _t('BIBLIOTHÈQUE', 'LIBRARY');
  String get coverFlow => 'Cover Flow';
  String get songs => _t('Morceaux', 'Songs');
  String get artists => _t('Artistes', 'Artists');
  String get genres => 'Genres';
  String get playlists => 'ALBUMS';
  String get newPlaylist => _t('Nouvel album', 'New album');
  String get tools => _t('OUTILS', 'TOOLS');
  String get toRepair => _t('À réparer', 'To repair');
  String get play => _t('Lecture', 'Play');
  String get shuffle => _t('Aléatoire', 'Shuffle');
  String get repair => _t('Réparer', 'Repair');
  String get playlistLabel => 'ALBUM';
  String get artistHeader => _t('ARTISTE', 'ARTIST');
  String get genreLabel => 'GENRE';
  String get toRepairLabel => _t('À RÉPARER', 'TO REPAIR');
  String get searchLabel => _t('RECHERCHE', 'SEARCH');
  String get albumHeader => 'ALBUM';
  String get skins => 'Skins';
  String unreadableSkin(String name) =>
      _t('Skin illisible : $name', 'Unreadable skin: $name');
  String get doubleSize =>
      _t('Taille double (Cmd + D)', 'Double size (Cmd + D)');
  String get backToLafleur =>
      _t('Revenir à LAFLEURMUSIC', 'Back to LAFLEURMUSIC');
  String get gridView => _t('Grille', 'Grid');
  String get listView => _t('Liste', 'List');
  String get theArtist => _t('L’ARTISTE', 'THE ARTIST');
  String get readMore => _t('Lire la suite', 'Read more');
  String get showLess => _t('Réduire', 'Show less');
  String get wikiSource =>
      _t('Source : Wikipédia (CC BY-SA)', 'Source: Wikipedia (CC BY-SA)');
  String artistKind(String kind) => switch (kind) {
    'group' => _t('Groupe', 'Band'),
    _ => _t('Artiste', 'Artist'),
  };
  String since(String year) => _t('depuis $year', 'since $year');
  String nSongs(int n) => _t('$n morceaux', '$n songs');
  String minutes(int n) => '$n min';
  String get nowPlaying => _t('EN COURS', 'NOW PLAYING');
  String get upNext => _t('À SUIVRE', 'UP NEXT');
  String get search => _t('Rechercher', 'Search');
  String get unknownArtist => _t('Inconnu', 'Unknown');
  String get nasMissing => _t(
    'NAS introuvable : les morceaux réapparaîtront quand il sera connecté.',
    'NAS not found: the songs will come back once it is connected.',
  );
  String get title => _t('TITRE', 'TITLE');
  String get artist => _t('ARTISTE', 'ARTIST');
  String get duration => _t('DURÉE', 'TIME');
  String noMusicIn(String path) => _t(
    'Aucune musique trouvée dans $path. Choisis un autre dossier.',
    'No music found in $path. Choose another folder.',
  );
  String get equalizer => _t('Égaliseur', 'Equalizer');
  String presetName(String key) => switch (key) {
    'flat' => _t('Plat', 'Flat'),
    'bass' => _t('Basses', 'Bass'),
    'vocal' => _t('Voix', 'Vocal'),
    'rock' => 'Rock',
    'electro' => _t('Électro', 'Electro'),
    _ => _t('Mon réglage', 'My setting'),
  };
  String nOfM(int n, int m, String album) =>
      _t('$n sur $m · $album', '$n of $m · $album');
  String cannotWrite(String path) => _t(
    'Impossible de modifier ${path.split('/').last} (fichier en lecture seule ?)',
    'Could not change ${path.split('/').last} (read-only file?)',
  );
  String repairTitle(String album) =>
      _t('Réparer « $album »', 'Repair “$album”');
  String get repairSource => _t(
    'Trouvé sur MusicBrainz et Cover Art Archive · vérifie avant d’enregistrer dans les fichiers',
    'Found on MusicBrainz and Cover Art Archive · check before saving to the files',
  );
  String get before => _t('AVANT', 'BEFORE');
  String get after => _t('APRÈS', 'AFTER');
  String get noCover => _t('pas de pochette', 'no cover');
  String get albumLabel => 'Album';
  String get artistLabel => _t('Artiste', 'Artist');
  String trackLabel(int n) => _t('Piste $n', 'Track $n');
  String get cancel => _t('Annuler', 'Cancel');
  String get otherResult => _t('Autre résultat', 'Other result');
  String saveIn(int n) =>
      _t('Enregistrer dans $n morceaux', 'Save to $n songs');
  String get searching => _t('Je cherche…', 'Searching…');
  String get nothingFound => _t(
    'Rien trouvé sur MusicBrainz pour cet album.',
    'Nothing found on MusicBrainz for this album.',
  );
  String get offline => _t(
    'Pas de connexion, réessaie plus tard.',
    'No connection, try again later.',
  );
  String get escToQuit =>
      _t('Échap pour quitter le plein écran', 'Esc to leave full screen');
  String get openPlaylist => _t('Ouvrir l’album', 'Open album');
  String get coverFlowHelp => _t(
    'Molette, trackpad ou ← → pour défiler · Entrée pour jouer',
    'Wheel, trackpad or ← → to browse · Enter to play',
  );
  // téléphone couché (maquette 2, écran 5)
  String get coverFlowHelpPhone => _t(
    'Glisse pour défiler · touche pour jouer',
    'Swipe to browse · tap to play',
  );
  String keptOnDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t('sur ${d.frThe.replaceAll("'", '’')}', 'on ${d.enThe}');
  }

  String playlistN(int n) => _t('Album · $n morceaux', 'Album · $n songs');
  String get scanning => _t('Je range ta musique…', 'Sorting your music…');

  // plan 5 : menu d'un morceau, Supprimer, Remplacer, Modifier
  String get playNextAction => _t('Lire ensuite', 'Play next');
  String get addToQueue => _t('Ajouter à la file', 'Add to queue');
  String get editTrack => _t('Modifier…', 'Edit…');
  String get replaceWith => _t('Remplacer par…', 'Replace with…');
  String get deleteTrack => _t('Supprimer le morceau…', 'Delete song…');
  String deleteQuestion(String title) =>
      _t('Supprimer « $title » ?', 'Delete “$title”?');
  String deleteExplain(String album) => _t(
    "Le fichier part à la Corbeille du Mac (tu peux le récupérer). Il disparaît de l'album $album.",
    'The file goes to the Mac Trash (you can get it back). It leaves the album $album.',
  );
  String get renumberHead => _t(
    'Renumérotation automatique (dans les tags) :',
    'Automatic renumbering (in the tags):',
  );
  String albumNowHas(int n) =>
      _t("L'album passe à $n morceaux.", 'The album now has $n songs.');
  String get deleteAction => _t('Supprimer', 'Delete');
  String replaceTitle(String title) =>
      _t('Remplacer « $title »', 'Replace “$title”');
  String newFile(String name) =>
      _t('Nouveau fichier : $name', 'New file: $name');
  String get replaceAction => _t('Remplacer', 'Replace');
  String editTitle(String title) => _t('Modifier « $title »', 'Edit “$title”');
  String get save => _t('Enregistrer', 'Save');
  String get fieldTitle => _t('TITRE', 'TITLE');
  String get fieldArtist => _t('ARTISTE', 'ARTIST');
  String get fieldAlbum => 'ALBUM';
  String get fieldNo => _t('N°', 'NO.');
  String get replaceNote => _t(
    "Titre et artiste : ceux du nouveau fichier. Album, numéro et pochette : ceux de l'ancien. Tout se modifie ici avant de valider.\nL'ancien fichier part à la Corbeille du Mac.",
    'Title and artist: from the new file. Album, number and cover: from the old one. Change anything here before confirming.\nThe old file goes to the Mac Trash.',
  );
  String trashFailed(String file) => _t(
    'Impossible de mettre « $file » à la Corbeille',
    'Could not move “$file” to the Trash',
  );
  String notAudio(String file) => _t(
    "« $file » n'est pas un fichier audio lisible",
    '“$file” is not a readable audio file',
  );
  String get addedByYou => _t('AJOUTÉS PAR TOI', 'ADDED BY YOU');
  String get nextInAlbum => _t("SUITE DE L'ALBUM", 'NEXT IN ALBUM');
  String get clearQueue => _t('Vider', 'Clear');
  // plan 5 : Top 100
  String get top100 => 'Top 100';
  String get topLabel => 'TOP 100';
  String get mostPlayed => _t('Les plus écoutés', 'Most played');
  String get playsHeader => _t('ÉCOUTES', 'PLAYS');
  String get playRule => _t(
    'Une écoute compte quand tu as écouté la moitié du morceau (ou 4 min).',
    'A play counts once you have heard half of the song (or 4 min).',
  );
  String get topEmpty => _t(
    'Rien encore : écoute un peu de musique.',
    'Nothing yet: play some music.',
  );
  // plan 5 : carte Lecture (maquette 9b)
  String get playbackCard => _t('Lecture', 'Playback');
  String get equalVolume => _t('Volume égal', 'Equal volume');
  String get equalVolumeHint => _t(
    'Tous les morceaux au même niveau sonore (ReplayGain). Mesuré une fois par morceau, puis gardé.',
    'Every song at the same loudness (ReplayGain). Measured once per song, then kept.',
  );
  String get crossfadeLabel => _t('Fondu enchaîné', 'Crossfade');
  String get crossfadeHint => _t(
    "La fin d'un morceau se fond dans le début du suivant.",
    'The end of a song blends into the start of the next.',
  );
  String seconds(int n) => '$n s';
  // plan 1 (téléphone) : écrans debout (maquette 1)
  String get home => _t('Accueil', 'Home');
  String get back => _t('Retour', 'Back'); // tablette : pas d'Accueil
  String get albumsBack => 'Albums';

  /// Accueil, sous les albums (maquette 7, écran 10).
  String get serverPlaylists => _t('PLAYLISTS DU SERVEUR', 'SERVER PLAYLISTS');

  /// En-tête d'une playlist du serveur (maquette 7, écran 11).
  String playlistOf(String account) => 'PLAYLIST · ${account.toUpperCase()}';

  /// Sous-titre d'un morceau de playlist.
  String artistAlbum(String artist, String album) => '$artist · $album';

  /// Un morceau de la playlist que son compte n'a pas (grisé).
  String get missingSong => _t('Morceau absent', 'Missing song');

  /// Retirer un album ou une playlist dont chaque morceau est gardé autrement : rien ne part.
  String get stillKeptElsewhere => _t(
    'Toujours gardé par un autre album ou une playlist.',
    'Still kept by another album or playlist.',
  );
  String notOnAccount(String account) =>
      _t('absent de $account', 'not on $account');
  String get allAccounts => _t('Tout', 'All');
  // Tout nom d'appareil passe par [_Dev] : iPhone, iPad (iOS), téléphone, tablette (Android)
  String onDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t('Sur ${d.frMy}', 'On my ${d.enName}');
  }

  String get upNextTab => _t('À suivre', 'Up next');
  String get swipePlayNext => '← $playNextAction';
  String unreadableSkipped(String title) =>
      _t('Illisible, passé : $title', 'Unreadable, skipped: $title');
  // plan 1 (téléphone) : comptes (maquette 2, écrans 6 et 7)
  String get accountsBack => _t('Comptes', 'Accounts');
  String get myAccounts => _t('MES COMPTES', 'MY ACCOUNTS');
  // « glisse ⋮⋮ pour l'ordre » : ⋮⋮ est l'icône de la poignée, entre les deux
  String get dragHint => _t('glisse', 'drag');
  String get toReorder => _t("pour l'ordre", 'to reorder');
  String accountState(AccountState st) => switch (st) {
    AccountState.connected => _t('● connecté', '● connected'),
    AccountState.absent => _t('● absent', '● unavailable'),
    AccountState.syncing => _t('synchronisation…', 'syncing…'),
    AccountState.checking => '…',
    AccountState.relink => plexRelink,
  };
  String typeName(AccountType t) => switch (t) {
    AccountType.subsonic => 'Subsonic',
    AccountType.jellyfin => 'Jellyfin',
    AccountType.plex => 'Plex',
  };
  String nHeaders(int n) =>
      n == 1 ? _t('1 en-tête', '1 header') : _t('$n en-têtes', '$n headers');
  String get addAccount => _t('+ Ajouter un compte', '+ Add an account');
  String get display => _t('AFFICHAGE', 'DISPLAY');
  String get oneAccount => _t('Un compte', 'One account');
  String get customDisplay => _t('Perso', 'Custom');
  String get soon => _t('bientôt', 'soon');
  String sameAlbumNote(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      "Un album présent sur deux comptes n'apparaît qu'une fois : il joue depuis ${d.frThe}, sinon depuis le premier compte de la liste.",
      'An album on two accounts shows only once: it plays from ${d.enThe}, otherwise from the first account in the list.',
    );
  }

  String get serverType => _t('TYPE DE SERVEUR', 'SERVER TYPE');
  String get subsonicServers => 'Navidrome, Airsonic, Gonic, LMS, Ampache…';
  String get fieldName => _t('NOM', 'NAME');
  String get fieldAddress => _t('ADRESSE', 'ADDRESS');
  String get fieldUser => _t('UTILISATEUR', 'USER');
  String get fieldPassword => _t('MOT DE PASSE', 'PASSWORD');
  String get passwordUnchanged => _t('inchangé', 'unchanged');
  String get fieldHeaders =>
      _t('EN-TÊTES HTTP (FACULTATIF)', 'HTTP HEADERS (OPTIONAL)');
  String get headerName => _t('En-tête', 'Header');
  String get headerValue => _t('Valeur', 'Value');
  String get addHeader => _t('+ Ajouter un en-tête', '+ Add a header');
  String get testAction => _t('Tester', 'Test');
  String get useHttps => _t(
    'Le serveur demande https:// : adresse corrigée.',
    'The server asks for https://: address fixed.',
  );
  String get testing => _t('Je teste…', 'Testing…');
  String testResult(TestResult r) => switch (r) {
    TestResult.ok => _t('Ça marche !', 'It works!'),
    TestResult.unreachable => _t('Serveur injoignable', 'Server unreachable'),
    TestResult.wrongPassword => _t(
      'Mauvais nom ou mot de passe',
      'Wrong name or password',
    ),
    TestResult.headerRefused => _t(
      'En-tête refusé par le proxy',
      'Header refused by the proxy',
    ),
    TestResult.notSubsonic => _t(
      "Ce n'est pas un serveur Subsonic",
      'This is not a Subsonic server',
    ),
    TestResult.notJellyfin => _t(
      "Ce n'est pas un serveur Jellyfin",
      'This is not a Jellyfin server',
    ),
    TestResult.certificateRejected => _t(
      'Certificat refusé (https)',
      'Certificate rejected (https)',
    ),
    TestResult.tokenRevoked => plexRelink,
  };

  // plan 5 : Plex, connexion par code (maquette 14)
  String get fieldAccountName => _t('NOM DU COMPTE', 'ACCOUNT NAME');
  String get plexHint => _t(
    "Pas de mot de passe à taper ici. L'appli te donne un code, tu le tapes sur plex.tv/link (sur ce téléphone ou un ordinateur), et c'est tout.",
    'No password to type here. The app gives you a code, you type it on plex.tv/link (on this phone or a computer), and that’s it.',
  );
  String get plexSignIn => _t('Se connecter avec Plex', 'Sign in with Plex');
  String get plexYourCode => _t('Ton code Plex', 'Your Plex code');
  String get plexGoTo => _t('Va sur ', 'Go to ');
  String get plexLinkSite => 'plex.tv/link';
  String get plexTypeIt =>
      _t(',\nconnecte-toi et tape ce code.', ',\nsign in and type this code.');
  String get plexOpenLink => _t('Ouvrir plex.tv/link', 'Open plex.tv/link');
  String get plexCopyCode => _t('Copier le code', 'Copy the code');
  String get plexWaiting => _t('En attente de Plex…', 'Waiting for Plex…');
  String get plexCodeLasts =>
      _t('Le code marche 15 minutes.', 'The code works for 15 minutes.');
  String get plexCodeExpired => _t('Code expiré', 'Code expired');
  String get plexNewCode => _t('Nouveau code', 'New code');
  String get plexDone => _t("C'est bon ✓", 'All set ✓');
  String plexWhichServer(int n) => _t(
    'Ton compte Plex a $n serveurs. Lequel ?',
    'Your Plex account has $n servers. Which one?',
  );
  String get plexAdd => _t('Ajouter', 'Add');
  String get plexAtHome => _t('À la maison', 'At home');
  String get plexOverInternet => _t('Par Internet', 'Over the Internet');
  String get plexNoAnswer => _t('Ne répond pas', 'Not answering');
  String plexMusicLibraries(int n) => n == 1
      ? _t('1 bibliothèque musique', '1 music library')
      : _t('$n bibliothèques musique', '$n music libraries');
  String get plexNoServer => _t(
    'Aucun serveur Plex sur ce compte.',
    'No Plex server on this account.',
  );
  String get plexTvUnreachable =>
      _t('plex.tv ne répond pas.', 'plex.tv is not answering.');
  String get plexServerGone => _t(
    "Ce serveur n'est plus sur ce compte Plex.",
    'This server is no longer on this Plex account.',
  );
  String get plexRelink => _t('À reconnecter', 'Sign in again');
  String get plexKeptStillPlays => _t(
    'Ta musique gardée sur le téléphone reste là et continue de jouer.',
    'Music kept on the phone stays there and keeps playing.',
  );

  /// iPhone, serveur de la maison injoignable : l'accès au réseau local a peut-être été refusé.
  String get localNetworkHint => _t(
    "Vérifie aussi que l'accès au réseau local est autorisé dans Réglages → LAFLEURMUSIC.",
    'Also check that local network access is allowed in Settings → LAFLEURMUSIC.',
  );
  String draftProblem(DraftProblem p) => switch (p) {
    DraftProblem.missing => _t(
      "Il manque l'adresse, l'utilisateur ou le mot de passe.",
      'The address, user or password is missing.',
    ),
    DraftProblem.badAddress => _t(
      'Adresse illisible : par exemple http://192.168.1.20:4533',
      'Unreadable address: for example http://192.168.1.20:4533',
    ),
  };
  String get saveFailed =>
      _t("Impossible d'enregistrer le compte.", 'Could not save the account.');
  String get firstAccount => _t(
    'Ajoute ton serveur de musique pour commencer.',
    'Add your music server to get started.',
  );
  String get deleteAccount => _t('Supprimer le compte', 'Delete account');
  String deleteAccountQuestion(String name) =>
      _t('Supprimer « $name » ?', 'Delete “$name”?');
  String get deleteAccountExplain => _t(
    'Ses morceaux disparaissent de ce téléphone ; rien n’est effacé sur le serveur.',
    'Its songs leave this phone; nothing is erased on the server.',
  );
  String get offlineLabel => _t('Hors ligne', 'Offline');
  String get folderNotLocal => _t(
    'Ce dossier n’est pas sur le téléphone. Choisis un dossier du téléphone ou de la carte SD.',
    'This folder isn’t on the phone. Pick a folder on the phone or SD card.',
  );
  String get folderNotWritable => _t(
    'L’appli ne peut pas écrire dans ce dossier. Choisis-en un autre, par exemple dans Musique.',
    'The app can’t write to this folder. Pick another one, for example in Music.',
  );

  // plan 2 : garder hors ligne (maquettes 1 et 2, écrans 2, 4 et 8)
  String get select => _t('Sélectionner…', 'Select…');
  String keepOnDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t('Garder sur ${d.frMy}', 'Keep on my ${d.enName}');
  }

  // (téléphone : « du téléphone » même sur iPhone, comme depuis le plan 2)
  String removeFromDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      tablet ? 'Retirer ${d.frFrom}' : 'Retirer du téléphone',
      'Remove from ${d.enName}',
    );
  }

  String albumsSelected(int n) => _t(
    'ALBUMS · $n ${n > 1 ? 'SÉLECTIONNÉS' : 'SÉLECTIONNÉ'}',
    'ALBUMS · $n SELECTED',
  );
  String get alreadyKept => _t('déjà gardé', 'already kept');
  String spaceOnDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      'PLACE SUR ${d.frThe}'.toUpperCase(),
      'SPACE ON ${d.enThe}'.toUpperCase(),
    );
  }

  String usedOf(String used, String limit) =>
      _t('$used utilisés sur $limit', '$used used of $limit');
  String filesHint(bool iphone, {bool tablet = false}) => iphone
      ? _t(
          "Les fichiers vont dans Fichiers → ${onDevice(iphone, tablet: tablet)} → LAFLEURMUSIC. Pour les mettre sur ton NAS, copie-les avec l'appli Fichiers.",
          'The files go in Files → ${onDevice(iphone, tablet: tablet).replaceFirst('my', 'My')} → LAFLEURMUSIC. To put them on your NAS, copy them with the Files app.',
        )
      : _t(
          'Les fichiers vont dans Musique/LAFLEURMUSIC. Pour les mettre sur ton NAS, copie-les avec une appli de fichiers.',
          'The files go in Music/LAFLEURMUSIC. To put them on your NAS, copy them with a file app.',
        );
  String keepButton(bool iphone, String? size, {bool tablet = false}) {
    final keep = keepOnDevice(iphone, tablet: tablet);
    return size == null ? keep : '$keep · $size';
  }

  String notEnoughSpace(String size) => _t(
    'Pas assez de place : il faut encore $size.',
    'Not enough space: $size more needed.',
  );
  String alreadyOnDevice(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      'Déjà sur ${d.frThe}. Appui long sur un morceau pour le retirer.',
      'Already on ${d.enThe}. Long-press a song to remove it.',
    );
  }

  String get keepFailed =>
      _t('Impossible de garder ces morceaux.', 'Could not keep these songs.');
  String get storageDenied => _t(
    "L'appli n'a pas le droit d'écrire dans Musique. Autorise-la dans les réglages du téléphone.",
    "The app isn't allowed to write to Music. Allow it in the phone settings.",
  );
  String notOnDevice(String artist, bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t('$artist · pas sur ${d.frThe}', '$artist · not on ${d.enThe}');
  }

  String nothingOffline(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      'Pas sur ${d.frThe} : rien à jouer hors ligne.',
      'Not on ${d.enThe}: nothing to play offline.',
    );
  }

  // plan 2 : écran « Sur mon iPhone » (maquette 4)
  String inProgress(int waiting) => waiting > 0
      ? _t('EN COURS · $waiting EN ATTENTE', 'DOWNLOADING · $waiting WAITING')
      : _t('EN COURS', 'DOWNLOADING');
  String get keptSection => _t('GARDÉS', 'KEPT');
  String get toRetry => _t('À RÉESSAYER', 'TO RETRY');
  String get retry => _t('Réessayer', 'Retry');
  String get notFoundOnServer =>
      _t('Introuvable sur le serveur', 'Not found on the server');
  String get top100Tag => 'TOP 100';
  String songCount(int n) => _t(
    '$n ${n == 1 ? 'titre' : 'titres'}',
    '$n ${n == 1 ? 'song' : 'songs'}',
  );
  String get pause => _t('Pause', 'Pause');
  String get resume => _t('Reprendre', 'Resume');

  /// « 12,4 sur 19,6 Mo » : la progression d'un morceau.
  String mbOf(int done, int total) {
    String mb(int b) {
      final t = (b / (1024 * 1024)).toStringAsFixed(1);
      return fr ? t.replaceAll('.', ',') : t;
    }

    return _t(
      '${mb(done)} sur ${mb(total)} Mo',
      '${mb(done)} of ${mb(total)} MB',
    );
  }

  String removeHint(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      'Glisse un album vers la gauche, ou appuie longtemps, pour le retirer ${tablet ? d.frFrom : 'du téléphone'}. Il reste sur le serveur.',
      'Swipe an album left, or long-press, to remove it from ${tablet ? d.enThe : 'the phone'}. It stays on the server.',
    );
  }

  String get limitSection => _t('LIMITE', 'LIMIT');
  String get allTheFreeSpace =>
      _t('toute la place libre', 'all the free space');
  String get top100Hint => _t(
    "Le Top 100 se garde tout seul à la maison, en Wi-Fi, tant qu'il reste de la place. Ce que tu gardes toi-même n'est jamais retiré tout seul.",
    'The Top 100 keeps itself at home, on Wi-Fi, as long as there is room. What you keep yourself is never removed on its own.',
  );
  String get folderSection => _t('DOSSIER', 'FOLDER');
  String defaultFolder(bool iphone, {bool tablet = false}) => iphone
      ? _t(
          '${onDevice(iphone, tablet: tablet)} › LAFLEURMUSIC',
          '${onDevice(iphone, tablet: tablet).replaceFirst('my', 'My')} › LAFLEURMUSIC',
        )
      : _t('Musique › LAFLEURMUSIC', 'Music › LAFLEURMUSIC');
  String get chooseTheFolder => _t('Choisir le dossier…', 'Choose the folder…');
  String get moving => _t('Déplacement…', 'Moving…');
  String folderHint(bool iphone) => iphone
      ? _t(
          'iCloud Drive marche aussi. En changeant de dossier, les morceaux gardés y sont déplacés.',
          'iCloud Drive works too. When you change folder, the kept songs are moved there.',
        )
      : _t(
          'Une carte SD marche aussi. En changeant de dossier, les morceaux gardés y sont déplacés.',
          'An SD card works too. When you change folder, the kept songs are moved there.',
        );
  String folderUnavailable(bool iphone, {bool tablet = false}) => _t(
    "Le dossier choisi n'est pas disponible. Branche-le ou choisis-en un autre dans ${onDevice(iphone, tablet: tablet)}.",
    "The chosen folder isn't available. Reconnect it or pick another one in ${onDevice(iphone, tablet: tablet)}.",
  );
  String get oldFolderMissing =>
      _t("L'ancien dossier est introuvable", "The old folder can't be found");
  String get oldFolderMissingExplain => _t(
    "L'appli ne peut pas y prendre tes morceaux gardés. Ils restent là-bas. Dans ce nouveau dossier, tu pourras les retélécharger avec « Réessayer ».",
    "The app can't take your kept songs from it. They stay there. In this new folder you can download them again with “Retry”.",
  );
  String get findOldFolder =>
      _t("Chercher l'ancien dossier", 'Find the old folder');
  String get relinkNotFound => _t(
    'Ce dossier ne contient pas tes morceaux gardés.',
    "This folder doesn't contain your kept songs.",
  );
  String get relinked => _t(
    'Ancien dossier retrouvé. Choisis maintenant le nouveau dossier.',
    'Old folder found. Now pick the new folder.',
  );
  String get useThisFolder => _t('Utiliser ce dossier', 'Use this folder');
  String get folderMoveFailed => _t(
    "Le dossier n'a pas pu être changé. Rien n'a été déplacé.",
    "The folder couldn't be changed. Nothing was moved.",
  );

  // confirmation avant « Retirer du téléphone » (maquette 10)
  String removeConfirmTitle(bool iphone, {bool tablet = false}) {
    final d = _Dev(iphone, tablet);
    return _t(
      tablet ? 'Retirer ${d.frFrom} ?' : 'Retirer du téléphone ?',
      'Remove from ${d.enThe}?',
    );
  }

  String removeConfirmBody(
    String name,
    int n,
    String size,
    bool iphone, {
    bool tablet = false,
  }) {
    final d = _Dev(iphone, tablet);
    return _t(
      '« $name » ($n ${n == 1 ? 'morceau' : 'morceaux'}, $size) sera effacé de ${d.frYour}. Il reste sur ton serveur : tu pourras le garder à nouveau.',
      '“$name” ($n ${n == 1 ? 'song' : 'songs'}, $size) will be erased from your ${d.enName}. It stays on your server: you can keep it again.',
    );
  }

  String get doNotAskAgain => _t('Ne plus me demander', "Don't ask me again");
  String get removeAction => _t('Retirer', 'Remove');
  String get confirmationsSection => _t('CONFIRMATIONS', 'CONFIRMATIONS');
  String get askBeforeRemoving =>
      _t('Demander avant de retirer', 'Ask before removing');
  String get askBeforeRemovingHint => _t(
    'Si tu as coché « Ne plus me demander », rallume-le ici.',
    'If you ticked “Don’t ask me again”, turn it back on here.',
  );

  /// Taille lisible : Mo en dessous d'un Go, sinon Go à une décimale (virgule en français).
  String size(int bytes) {
    const mb = 1024 * 1024, gb = 1024 * mb;
    if (bytes < gb) return '${(bytes / mb).round()} ${_t('Mo', 'MB')}';
    final g = (bytes / gb * 10).round() / 10;
    final text = g == g.roundToDouble() ? '${g.round()}' : g.toStringAsFixed(1);
    return '${fr ? text.replaceAll('.', ',') : text} ${_t('Go', 'GB')}';
  }
}

/// Le nom de l'appareil, au seul endroit où on le décide : iPhone / iPad sur iOS, téléphone / tablette sur
/// Android, avec ses articles (« l'iPad », « la tablette », « du téléphone »…).
class _Dev {
  const _Dev(this.ios, this.tablet);
  final bool ios, tablet;

  bool get _fem => tablet && !ios; // la tablette
  String get frName =>
      tablet ? (ios ? 'iPad' : 'tablette') : (ios ? 'iPhone' : 'téléphone');
  String get enName =>
      tablet ? (ios ? 'iPad' : 'tablet') : (ios ? 'iPhone' : 'phone');
  String get frThe => ios ? "l'$frName" : '${_fem ? 'la' : 'le'} $frName';
  String get enThe => 'the $enName';
  String get frMy => '${_fem ? 'ma' : 'mon'} $frName';
  String get frYour => '${_fem ? 'ta' : 'ton'} $frName';
  String get frFrom =>
      ios ? 'de l’$frName' : (_fem ? 'de la $frName' : 'du $frName');
}
