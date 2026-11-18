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
  String get albumsBack => 'Albums';
  String get allAccounts => _t('Tout', 'All');
  String onDevice(bool iphone) => iphone
      ? _t('Sur mon iPhone', 'On my iPhone')
      : _t('Sur mon téléphone', 'On my phone');
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
  String sameAlbumNote(bool iphone) => _t(
    "Un album présent sur deux comptes n'apparaît qu'une fois : il joue depuis ${iphone ? "l'iPhone" : 'le téléphone'}, sinon depuis le premier compte de la liste.",
    'An album on two accounts shows only once: it plays from ${iphone ? 'the iPhone' : 'the phone'}, otherwise from the first account in the list.',
  );
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
    TestResult.certificateRejected => _t(
      'Certificat refusé (https)',
      'Certificate rejected (https)',
    ),
  };

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
}
