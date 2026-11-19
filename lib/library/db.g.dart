// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, TrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _albumArtistMeta = const VerificationMeta(
    'albumArtist',
  );
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
    'album_artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _discMeta = const VerificationMeta('disc');
  @override
  late final GeneratedColumn<int> disc = GeneratedColumn<int>(
    'disc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverIdMeta = const VerificationMeta(
    'coverId',
  );
  @override
  late final GeneratedColumn<String> coverId = GeneratedColumn<String>(
    'cover_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suffixMeta = const VerificationMeta('suffix');
  @override
  late final GeneratedColumn<String> suffix = GeneratedColumn<String>(
    'suffix',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replayGainMeta = const VerificationMeta(
    'replayGain',
  );
  @override
  late final GeneratedColumn<double> replayGain = GeneratedColumn<double>(
    'replay_gain',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumKeyMeta = const VerificationMeta(
    'albumKey',
  );
  @override
  late final GeneratedColumn<String> albumKey = GeneratedColumn<String>(
    'album_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackNoMeta = const VerificationMeta(
    'trackNo',
  );
  @override
  late final GeneratedColumn<int> trackNo = GeneratedColumn<int>(
    'track_no',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasCoverMeta = const VerificationMeta(
    'hasCover',
  );
  @override
  late final GeneratedColumn<bool> hasCover = GeneratedColumn<bool>(
    'has_cover',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_cover" IN (0, 1))',
    ),
  );
  static const VerificationMeta _mtimeMeta = const VerificationMeta('mtime');
  @override
  late final GeneratedColumn<int> mtime = GeneratedColumn<int>(
    'mtime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missingMeta = const VerificationMeta(
    'missing',
  );
  @override
  late final GeneratedColumn<bool> missing = GeneratedColumn<bool>(
    'missing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("missing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _toRepairMeta = const VerificationMeta(
    'toRepair',
  );
  @override
  late final GeneratedColumn<bool> toRepair = GeneratedColumn<bool>(
    'to_repair',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("to_repair" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _searchKeyMeta = const VerificationMeta(
    'searchKey',
  );
  @override
  late final GeneratedColumn<String> searchKey = GeneratedColumn<String>(
    'search_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mergeKeyMeta = const VerificationMeta(
    'mergeKey',
  );
  @override
  late final GeneratedColumn<String> mergeKey = GeneratedColumn<String>(
    'merge_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _albumMergeKeyMeta = const VerificationMeta(
    'albumMergeKey',
  );
  @override
  late final GeneratedColumn<String> albumMergeKey = GeneratedColumn<String>(
    'album_merge_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    path,
    folderId,
    accountId,
    remoteId,
    albumArtist,
    disc,
    coverId,
    suffix,
    replayGain,
    title,
    artist,
    album,
    albumKey,
    genre,
    trackNo,
    durationMs,
    hasCover,
    mtime,
    size,
    missing,
    toRepair,
    searchKey,
    mergeKey,
    albumMergeKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('album_artist')) {
      context.handle(
        _albumArtistMeta,
        albumArtist.isAcceptableOrUnknown(
          data['album_artist']!,
          _albumArtistMeta,
        ),
      );
    }
    if (data.containsKey('disc')) {
      context.handle(
        _discMeta,
        disc.isAcceptableOrUnknown(data['disc']!, _discMeta),
      );
    }
    if (data.containsKey('cover_id')) {
      context.handle(
        _coverIdMeta,
        coverId.isAcceptableOrUnknown(data['cover_id']!, _coverIdMeta),
      );
    }
    if (data.containsKey('suffix')) {
      context.handle(
        _suffixMeta,
        suffix.isAcceptableOrUnknown(data['suffix']!, _suffixMeta),
      );
    }
    if (data.containsKey('replay_gain')) {
      context.handle(
        _replayGainMeta,
        replayGain.isAcceptableOrUnknown(data['replay_gain']!, _replayGainMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('album_key')) {
      context.handle(
        _albumKeyMeta,
        albumKey.isAcceptableOrUnknown(data['album_key']!, _albumKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_albumKeyMeta);
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('track_no')) {
      context.handle(
        _trackNoMeta,
        trackNo.isAcceptableOrUnknown(data['track_no']!, _trackNoMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('has_cover')) {
      context.handle(
        _hasCoverMeta,
        hasCover.isAcceptableOrUnknown(data['has_cover']!, _hasCoverMeta),
      );
    } else if (isInserting) {
      context.missing(_hasCoverMeta);
    }
    if (data.containsKey('mtime')) {
      context.handle(
        _mtimeMeta,
        mtime.isAcceptableOrUnknown(data['mtime']!, _mtimeMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('missing')) {
      context.handle(
        _missingMeta,
        missing.isAcceptableOrUnknown(data['missing']!, _missingMeta),
      );
    }
    if (data.containsKey('to_repair')) {
      context.handle(
        _toRepairMeta,
        toRepair.isAcceptableOrUnknown(data['to_repair']!, _toRepairMeta),
      );
    }
    if (data.containsKey('search_key')) {
      context.handle(
        _searchKeyMeta,
        searchKey.isAcceptableOrUnknown(data['search_key']!, _searchKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_searchKeyMeta);
    }
    if (data.containsKey('merge_key')) {
      context.handle(
        _mergeKeyMeta,
        mergeKey.isAcceptableOrUnknown(data['merge_key']!, _mergeKeyMeta),
      );
    }
    if (data.containsKey('album_merge_key')) {
      context.handle(
        _albumMergeKeyMeta,
        albumMergeKey.isAcceptableOrUnknown(
          data['album_merge_key']!,
          _albumMergeKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      albumArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_artist'],
      )!,
      disc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc'],
      ),
      coverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_id'],
      ),
      suffix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suffix'],
      ),
      replayGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}replay_gain'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      albumKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_key'],
      )!,
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      )!,
      trackNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_no'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      hasCover: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_cover'],
      )!,
      mtime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mtime'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      missing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}missing'],
      )!,
      toRepair: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}to_repair'],
      )!,
      searchKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_key'],
      )!,
      mergeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merge_key'],
      )!,
      albumMergeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_merge_key'],
      )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class TrackRow extends DataClass implements Insertable<TrackRow> {
  final int id;
  final String path;
  final int folderId;
  final String accountId;
  final String remoteId;
  final String albumArtist;
  final int? disc;
  final String? coverId;
  final String? suffix;
  final double? replayGain;
  final String title;
  final String artist;
  final String album;
  final String albumKey;
  final String genre;
  final int? trackNo;
  final int durationMs;
  final bool hasCover;
  final int mtime;
  final int size;
  final bool missing;
  final bool toRepair;
  final String searchKey;
  final String mergeKey;
  final String albumMergeKey;
  const TrackRow({
    required this.id,
    required this.path,
    required this.folderId,
    required this.accountId,
    required this.remoteId,
    required this.albumArtist,
    this.disc,
    this.coverId,
    this.suffix,
    this.replayGain,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumKey,
    required this.genre,
    this.trackNo,
    required this.durationMs,
    required this.hasCover,
    required this.mtime,
    required this.size,
    required this.missing,
    required this.toRepair,
    required this.searchKey,
    required this.mergeKey,
    required this.albumMergeKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    map['folder_id'] = Variable<int>(folderId);
    map['account_id'] = Variable<String>(accountId);
    map['remote_id'] = Variable<String>(remoteId);
    map['album_artist'] = Variable<String>(albumArtist);
    if (!nullToAbsent || disc != null) {
      map['disc'] = Variable<int>(disc);
    }
    if (!nullToAbsent || coverId != null) {
      map['cover_id'] = Variable<String>(coverId);
    }
    if (!nullToAbsent || suffix != null) {
      map['suffix'] = Variable<String>(suffix);
    }
    if (!nullToAbsent || replayGain != null) {
      map['replay_gain'] = Variable<double>(replayGain);
    }
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    map['album_key'] = Variable<String>(albumKey);
    map['genre'] = Variable<String>(genre);
    if (!nullToAbsent || trackNo != null) {
      map['track_no'] = Variable<int>(trackNo);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['has_cover'] = Variable<bool>(hasCover);
    map['mtime'] = Variable<int>(mtime);
    map['size'] = Variable<int>(size);
    map['missing'] = Variable<bool>(missing);
    map['to_repair'] = Variable<bool>(toRepair);
    map['search_key'] = Variable<String>(searchKey);
    map['merge_key'] = Variable<String>(mergeKey);
    map['album_merge_key'] = Variable<String>(albumMergeKey);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      path: Value(path),
      folderId: Value(folderId),
      accountId: Value(accountId),
      remoteId: Value(remoteId),
      albumArtist: Value(albumArtist),
      disc: disc == null && nullToAbsent ? const Value.absent() : Value(disc),
      coverId: coverId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverId),
      suffix: suffix == null && nullToAbsent
          ? const Value.absent()
          : Value(suffix),
      replayGain: replayGain == null && nullToAbsent
          ? const Value.absent()
          : Value(replayGain),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      albumKey: Value(albumKey),
      genre: Value(genre),
      trackNo: trackNo == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNo),
      durationMs: Value(durationMs),
      hasCover: Value(hasCover),
      mtime: Value(mtime),
      size: Value(size),
      missing: Value(missing),
      toRepair: Value(toRepair),
      searchKey: Value(searchKey),
      mergeKey: Value(mergeKey),
      albumMergeKey: Value(albumMergeKey),
    );
  }

  factory TrackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackRow(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      folderId: serializer.fromJson<int>(json['folderId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      albumArtist: serializer.fromJson<String>(json['albumArtist']),
      disc: serializer.fromJson<int?>(json['disc']),
      coverId: serializer.fromJson<String?>(json['coverId']),
      suffix: serializer.fromJson<String?>(json['suffix']),
      replayGain: serializer.fromJson<double?>(json['replayGain']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      albumKey: serializer.fromJson<String>(json['albumKey']),
      genre: serializer.fromJson<String>(json['genre']),
      trackNo: serializer.fromJson<int?>(json['trackNo']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      hasCover: serializer.fromJson<bool>(json['hasCover']),
      mtime: serializer.fromJson<int>(json['mtime']),
      size: serializer.fromJson<int>(json['size']),
      missing: serializer.fromJson<bool>(json['missing']),
      toRepair: serializer.fromJson<bool>(json['toRepair']),
      searchKey: serializer.fromJson<String>(json['searchKey']),
      mergeKey: serializer.fromJson<String>(json['mergeKey']),
      albumMergeKey: serializer.fromJson<String>(json['albumMergeKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'folderId': serializer.toJson<int>(folderId),
      'accountId': serializer.toJson<String>(accountId),
      'remoteId': serializer.toJson<String>(remoteId),
      'albumArtist': serializer.toJson<String>(albumArtist),
      'disc': serializer.toJson<int?>(disc),
      'coverId': serializer.toJson<String?>(coverId),
      'suffix': serializer.toJson<String?>(suffix),
      'replayGain': serializer.toJson<double?>(replayGain),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'albumKey': serializer.toJson<String>(albumKey),
      'genre': serializer.toJson<String>(genre),
      'trackNo': serializer.toJson<int?>(trackNo),
      'durationMs': serializer.toJson<int>(durationMs),
      'hasCover': serializer.toJson<bool>(hasCover),
      'mtime': serializer.toJson<int>(mtime),
      'size': serializer.toJson<int>(size),
      'missing': serializer.toJson<bool>(missing),
      'toRepair': serializer.toJson<bool>(toRepair),
      'searchKey': serializer.toJson<String>(searchKey),
      'mergeKey': serializer.toJson<String>(mergeKey),
      'albumMergeKey': serializer.toJson<String>(albumMergeKey),
    };
  }

  TrackRow copyWith({
    int? id,
    String? path,
    int? folderId,
    String? accountId,
    String? remoteId,
    String? albumArtist,
    Value<int?> disc = const Value.absent(),
    Value<String?> coverId = const Value.absent(),
    Value<String?> suffix = const Value.absent(),
    Value<double?> replayGain = const Value.absent(),
    String? title,
    String? artist,
    String? album,
    String? albumKey,
    String? genre,
    Value<int?> trackNo = const Value.absent(),
    int? durationMs,
    bool? hasCover,
    int? mtime,
    int? size,
    bool? missing,
    bool? toRepair,
    String? searchKey,
    String? mergeKey,
    String? albumMergeKey,
  }) => TrackRow(
    id: id ?? this.id,
    path: path ?? this.path,
    folderId: folderId ?? this.folderId,
    accountId: accountId ?? this.accountId,
    remoteId: remoteId ?? this.remoteId,
    albumArtist: albumArtist ?? this.albumArtist,
    disc: disc.present ? disc.value : this.disc,
    coverId: coverId.present ? coverId.value : this.coverId,
    suffix: suffix.present ? suffix.value : this.suffix,
    replayGain: replayGain.present ? replayGain.value : this.replayGain,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    albumKey: albumKey ?? this.albumKey,
    genre: genre ?? this.genre,
    trackNo: trackNo.present ? trackNo.value : this.trackNo,
    durationMs: durationMs ?? this.durationMs,
    hasCover: hasCover ?? this.hasCover,
    mtime: mtime ?? this.mtime,
    size: size ?? this.size,
    missing: missing ?? this.missing,
    toRepair: toRepair ?? this.toRepair,
    searchKey: searchKey ?? this.searchKey,
    mergeKey: mergeKey ?? this.mergeKey,
    albumMergeKey: albumMergeKey ?? this.albumMergeKey,
  );
  TrackRow copyWithCompanion(TracksCompanion data) {
    return TrackRow(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      albumArtist: data.albumArtist.present
          ? data.albumArtist.value
          : this.albumArtist,
      disc: data.disc.present ? data.disc.value : this.disc,
      coverId: data.coverId.present ? data.coverId.value : this.coverId,
      suffix: data.suffix.present ? data.suffix.value : this.suffix,
      replayGain: data.replayGain.present
          ? data.replayGain.value
          : this.replayGain,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      albumKey: data.albumKey.present ? data.albumKey.value : this.albumKey,
      genre: data.genre.present ? data.genre.value : this.genre,
      trackNo: data.trackNo.present ? data.trackNo.value : this.trackNo,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      hasCover: data.hasCover.present ? data.hasCover.value : this.hasCover,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
      size: data.size.present ? data.size.value : this.size,
      missing: data.missing.present ? data.missing.value : this.missing,
      toRepair: data.toRepair.present ? data.toRepair.value : this.toRepair,
      searchKey: data.searchKey.present ? data.searchKey.value : this.searchKey,
      mergeKey: data.mergeKey.present ? data.mergeKey.value : this.mergeKey,
      albumMergeKey: data.albumMergeKey.present
          ? data.albumMergeKey.value
          : this.albumMergeKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('folderId: $folderId, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('disc: $disc, ')
          ..write('coverId: $coverId, ')
          ..write('suffix: $suffix, ')
          ..write('replayGain: $replayGain, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumKey: $albumKey, ')
          ..write('genre: $genre, ')
          ..write('trackNo: $trackNo, ')
          ..write('durationMs: $durationMs, ')
          ..write('hasCover: $hasCover, ')
          ..write('mtime: $mtime, ')
          ..write('size: $size, ')
          ..write('missing: $missing, ')
          ..write('toRepair: $toRepair, ')
          ..write('searchKey: $searchKey, ')
          ..write('mergeKey: $mergeKey, ')
          ..write('albumMergeKey: $albumMergeKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    path,
    folderId,
    accountId,
    remoteId,
    albumArtist,
    disc,
    coverId,
    suffix,
    replayGain,
    title,
    artist,
    album,
    albumKey,
    genre,
    trackNo,
    durationMs,
    hasCover,
    mtime,
    size,
    missing,
    toRepair,
    searchKey,
    mergeKey,
    albumMergeKey,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.id == this.id &&
          other.path == this.path &&
          other.folderId == this.folderId &&
          other.accountId == this.accountId &&
          other.remoteId == this.remoteId &&
          other.albumArtist == this.albumArtist &&
          other.disc == this.disc &&
          other.coverId == this.coverId &&
          other.suffix == this.suffix &&
          other.replayGain == this.replayGain &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.albumKey == this.albumKey &&
          other.genre == this.genre &&
          other.trackNo == this.trackNo &&
          other.durationMs == this.durationMs &&
          other.hasCover == this.hasCover &&
          other.mtime == this.mtime &&
          other.size == this.size &&
          other.missing == this.missing &&
          other.toRepair == this.toRepair &&
          other.searchKey == this.searchKey &&
          other.mergeKey == this.mergeKey &&
          other.albumMergeKey == this.albumMergeKey);
}

class TracksCompanion extends UpdateCompanion<TrackRow> {
  final Value<int> id;
  final Value<String> path;
  final Value<int> folderId;
  final Value<String> accountId;
  final Value<String> remoteId;
  final Value<String> albumArtist;
  final Value<int?> disc;
  final Value<String?> coverId;
  final Value<String?> suffix;
  final Value<double?> replayGain;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String> albumKey;
  final Value<String> genre;
  final Value<int?> trackNo;
  final Value<int> durationMs;
  final Value<bool> hasCover;
  final Value<int> mtime;
  final Value<int> size;
  final Value<bool> missing;
  final Value<bool> toRepair;
  final Value<String> searchKey;
  final Value<String> mergeKey;
  final Value<String> albumMergeKey;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.folderId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.disc = const Value.absent(),
    this.coverId = const Value.absent(),
    this.suffix = const Value.absent(),
    this.replayGain = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.albumKey = const Value.absent(),
    this.genre = const Value.absent(),
    this.trackNo = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.hasCover = const Value.absent(),
    this.mtime = const Value.absent(),
    this.size = const Value.absent(),
    this.missing = const Value.absent(),
    this.toRepair = const Value.absent(),
    this.searchKey = const Value.absent(),
    this.mergeKey = const Value.absent(),
    this.albumMergeKey = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    this.folderId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.disc = const Value.absent(),
    this.coverId = const Value.absent(),
    this.suffix = const Value.absent(),
    this.replayGain = const Value.absent(),
    required String title,
    required String artist,
    required String album,
    required String albumKey,
    this.genre = const Value.absent(),
    this.trackNo = const Value.absent(),
    required int durationMs,
    required bool hasCover,
    this.mtime = const Value.absent(),
    required int size,
    this.missing = const Value.absent(),
    this.toRepair = const Value.absent(),
    required String searchKey,
    this.mergeKey = const Value.absent(),
    this.albumMergeKey = const Value.absent(),
  }) : path = Value(path),
       title = Value(title),
       artist = Value(artist),
       album = Value(album),
       albumKey = Value(albumKey),
       durationMs = Value(durationMs),
       hasCover = Value(hasCover),
       size = Value(size),
       searchKey = Value(searchKey);
  static Insertable<TrackRow> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<int>? folderId,
    Expression<String>? accountId,
    Expression<String>? remoteId,
    Expression<String>? albumArtist,
    Expression<int>? disc,
    Expression<String>? coverId,
    Expression<String>? suffix,
    Expression<double>? replayGain,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? albumKey,
    Expression<String>? genre,
    Expression<int>? trackNo,
    Expression<int>? durationMs,
    Expression<bool>? hasCover,
    Expression<int>? mtime,
    Expression<int>? size,
    Expression<bool>? missing,
    Expression<bool>? toRepair,
    Expression<String>? searchKey,
    Expression<String>? mergeKey,
    Expression<String>? albumMergeKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (folderId != null) 'folder_id': folderId,
      if (accountId != null) 'account_id': accountId,
      if (remoteId != null) 'remote_id': remoteId,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (disc != null) 'disc': disc,
      if (coverId != null) 'cover_id': coverId,
      if (suffix != null) 'suffix': suffix,
      if (replayGain != null) 'replay_gain': replayGain,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (albumKey != null) 'album_key': albumKey,
      if (genre != null) 'genre': genre,
      if (trackNo != null) 'track_no': trackNo,
      if (durationMs != null) 'duration_ms': durationMs,
      if (hasCover != null) 'has_cover': hasCover,
      if (mtime != null) 'mtime': mtime,
      if (size != null) 'size': size,
      if (missing != null) 'missing': missing,
      if (toRepair != null) 'to_repair': toRepair,
      if (searchKey != null) 'search_key': searchKey,
      if (mergeKey != null) 'merge_key': mergeKey,
      if (albumMergeKey != null) 'album_merge_key': albumMergeKey,
    });
  }

  TracksCompanion copyWith({
    Value<int>? id,
    Value<String>? path,
    Value<int>? folderId,
    Value<String>? accountId,
    Value<String>? remoteId,
    Value<String>? albumArtist,
    Value<int?>? disc,
    Value<String?>? coverId,
    Value<String?>? suffix,
    Value<double?>? replayGain,
    Value<String>? title,
    Value<String>? artist,
    Value<String>? album,
    Value<String>? albumKey,
    Value<String>? genre,
    Value<int?>? trackNo,
    Value<int>? durationMs,
    Value<bool>? hasCover,
    Value<int>? mtime,
    Value<int>? size,
    Value<bool>? missing,
    Value<bool>? toRepair,
    Value<String>? searchKey,
    Value<String>? mergeKey,
    Value<String>? albumMergeKey,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      folderId: folderId ?? this.folderId,
      accountId: accountId ?? this.accountId,
      remoteId: remoteId ?? this.remoteId,
      albumArtist: albumArtist ?? this.albumArtist,
      disc: disc ?? this.disc,
      coverId: coverId ?? this.coverId,
      suffix: suffix ?? this.suffix,
      replayGain: replayGain ?? this.replayGain,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumKey: albumKey ?? this.albumKey,
      genre: genre ?? this.genre,
      trackNo: trackNo ?? this.trackNo,
      durationMs: durationMs ?? this.durationMs,
      hasCover: hasCover ?? this.hasCover,
      mtime: mtime ?? this.mtime,
      size: size ?? this.size,
      missing: missing ?? this.missing,
      toRepair: toRepair ?? this.toRepair,
      searchKey: searchKey ?? this.searchKey,
      mergeKey: mergeKey ?? this.mergeKey,
      albumMergeKey: albumMergeKey ?? this.albumMergeKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (disc.present) {
      map['disc'] = Variable<int>(disc.value);
    }
    if (coverId.present) {
      map['cover_id'] = Variable<String>(coverId.value);
    }
    if (suffix.present) {
      map['suffix'] = Variable<String>(suffix.value);
    }
    if (replayGain.present) {
      map['replay_gain'] = Variable<double>(replayGain.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumKey.present) {
      map['album_key'] = Variable<String>(albumKey.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (trackNo.present) {
      map['track_no'] = Variable<int>(trackNo.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (hasCover.present) {
      map['has_cover'] = Variable<bool>(hasCover.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<int>(mtime.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (missing.present) {
      map['missing'] = Variable<bool>(missing.value);
    }
    if (toRepair.present) {
      map['to_repair'] = Variable<bool>(toRepair.value);
    }
    if (searchKey.present) {
      map['search_key'] = Variable<String>(searchKey.value);
    }
    if (mergeKey.present) {
      map['merge_key'] = Variable<String>(mergeKey.value);
    }
    if (albumMergeKey.present) {
      map['album_merge_key'] = Variable<String>(albumMergeKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('folderId: $folderId, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('disc: $disc, ')
          ..write('coverId: $coverId, ')
          ..write('suffix: $suffix, ')
          ..write('replayGain: $replayGain, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('albumKey: $albumKey, ')
          ..write('genre: $genre, ')
          ..write('trackNo: $trackNo, ')
          ..write('durationMs: $durationMs, ')
          ..write('hasCover: $hasCover, ')
          ..write('mtime: $mtime, ')
          ..write('size: $size, ')
          ..write('missing: $missing, ')
          ..write('toRepair: $toRepair, ')
          ..write('searchKey: $searchKey, ')
          ..write('mergeKey: $mergeKey, ')
          ..write('albumMergeKey: $albumMergeKey')
          ..write(')'))
        .toString();
  }
}

class $PlayCountsTable extends PlayCounts
    with TableInfo<$PlayCountsTable, PlayCount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayCountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedMeta = const VerificationMeta(
    'imported',
  );
  @override
  late final GeneratedColumn<int> imported = GeneratedColumn<int>(
    'imported',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedMeta = const VerificationMeta(
    'lastPlayed',
  );
  @override
  late final GeneratedColumn<int> lastPlayed = GeneratedColumn<int>(
    'last_played',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [path, count, imported, lastPlayed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_counts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayCount> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('imported')) {
      context.handle(
        _importedMeta,
        imported.isAcceptableOrUnknown(data['imported']!, _importedMeta),
      );
    }
    if (data.containsKey('last_played')) {
      context.handle(
        _lastPlayedMeta,
        lastPlayed.isAcceptableOrUnknown(data['last_played']!, _lastPlayedMeta),
      );
    } else if (isInserting) {
      context.missing(_lastPlayedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  PlayCount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayCount(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      imported: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported'],
      )!,
      lastPlayed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_played'],
      )!,
    );
  }

  @override
  $PlayCountsTable createAlias(String alias) {
    return $PlayCountsTable(attachedDatabase, alias);
  }
}

class PlayCount extends DataClass implements Insertable<PlayCount> {
  final String path;
  final int count;
  final int imported;
  final int lastPlayed;
  const PlayCount({
    required this.path,
    required this.count,
    required this.imported,
    required this.lastPlayed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['count'] = Variable<int>(count);
    map['imported'] = Variable<int>(imported);
    map['last_played'] = Variable<int>(lastPlayed);
    return map;
  }

  PlayCountsCompanion toCompanion(bool nullToAbsent) {
    return PlayCountsCompanion(
      path: Value(path),
      count: Value(count),
      imported: Value(imported),
      lastPlayed: Value(lastPlayed),
    );
  }

  factory PlayCount.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayCount(
      path: serializer.fromJson<String>(json['path']),
      count: serializer.fromJson<int>(json['count']),
      imported: serializer.fromJson<int>(json['imported']),
      lastPlayed: serializer.fromJson<int>(json['lastPlayed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'count': serializer.toJson<int>(count),
      'imported': serializer.toJson<int>(imported),
      'lastPlayed': serializer.toJson<int>(lastPlayed),
    };
  }

  PlayCount copyWith({
    String? path,
    int? count,
    int? imported,
    int? lastPlayed,
  }) => PlayCount(
    path: path ?? this.path,
    count: count ?? this.count,
    imported: imported ?? this.imported,
    lastPlayed: lastPlayed ?? this.lastPlayed,
  );
  PlayCount copyWithCompanion(PlayCountsCompanion data) {
    return PlayCount(
      path: data.path.present ? data.path.value : this.path,
      count: data.count.present ? data.count.value : this.count,
      imported: data.imported.present ? data.imported.value : this.imported,
      lastPlayed: data.lastPlayed.present
          ? data.lastPlayed.value
          : this.lastPlayed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayCount(')
          ..write('path: $path, ')
          ..write('count: $count, ')
          ..write('imported: $imported, ')
          ..write('lastPlayed: $lastPlayed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, count, imported, lastPlayed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayCount &&
          other.path == this.path &&
          other.count == this.count &&
          other.imported == this.imported &&
          other.lastPlayed == this.lastPlayed);
}

class PlayCountsCompanion extends UpdateCompanion<PlayCount> {
  final Value<String> path;
  final Value<int> count;
  final Value<int> imported;
  final Value<int> lastPlayed;
  final Value<int> rowid;
  const PlayCountsCompanion({
    this.path = const Value.absent(),
    this.count = const Value.absent(),
    this.imported = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayCountsCompanion.insert({
    required String path,
    required int count,
    this.imported = const Value.absent(),
    required int lastPlayed,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       count = Value(count),
       lastPlayed = Value(lastPlayed);
  static Insertable<PlayCount> custom({
    Expression<String>? path,
    Expression<int>? count,
    Expression<int>? imported,
    Expression<int>? lastPlayed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (count != null) 'count': count,
      if (imported != null) 'imported': imported,
      if (lastPlayed != null) 'last_played': lastPlayed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayCountsCompanion copyWith({
    Value<String>? path,
    Value<int>? count,
    Value<int>? imported,
    Value<int>? lastPlayed,
    Value<int>? rowid,
  }) {
    return PlayCountsCompanion(
      path: path ?? this.path,
      count: count ?? this.count,
      imported: imported ?? this.imported,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (imported.present) {
      map['imported'] = Variable<int>(imported.value);
    }
    if (lastPlayed.present) {
      map['last_played'] = Variable<int>(lastPlayed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayCountsCompanion(')
          ..write('path: $path, ')
          ..write('count: $count, ')
          ..write('imported: $imported, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoudnessTable extends Loudness
    with TableInfo<$LoudnessTable, LoudnessData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoudnessTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lufsMeta = const VerificationMeta('lufs');
  @override
  late final GeneratedColumn<double> lufs = GeneratedColumn<double>(
    'lufs',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mtimeMeta = const VerificationMeta('mtime');
  @override
  late final GeneratedColumn<int> mtime = GeneratedColumn<int>(
    'mtime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [path, lufs, mtime];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loudness';
  @override
  VerificationContext validateIntegrity(
    Insertable<LoudnessData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('lufs')) {
      context.handle(
        _lufsMeta,
        lufs.isAcceptableOrUnknown(data['lufs']!, _lufsMeta),
      );
    }
    if (data.containsKey('mtime')) {
      context.handle(
        _mtimeMeta,
        mtime.isAcceptableOrUnknown(data['mtime']!, _mtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mtimeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  LoudnessData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LoudnessData(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      lufs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lufs'],
      ),
      mtime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mtime'],
      )!,
    );
  }

  @override
  $LoudnessTable createAlias(String alias) {
    return $LoudnessTable(attachedDatabase, alias);
  }
}

class LoudnessData extends DataClass implements Insertable<LoudnessData> {
  final String path;
  final double? lufs;
  final int mtime;
  const LoudnessData({required this.path, this.lufs, required this.mtime});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || lufs != null) {
      map['lufs'] = Variable<double>(lufs);
    }
    map['mtime'] = Variable<int>(mtime);
    return map;
  }

  LoudnessCompanion toCompanion(bool nullToAbsent) {
    return LoudnessCompanion(
      path: Value(path),
      lufs: lufs == null && nullToAbsent ? const Value.absent() : Value(lufs),
      mtime: Value(mtime),
    );
  }

  factory LoudnessData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LoudnessData(
      path: serializer.fromJson<String>(json['path']),
      lufs: serializer.fromJson<double?>(json['lufs']),
      mtime: serializer.fromJson<int>(json['mtime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'lufs': serializer.toJson<double?>(lufs),
      'mtime': serializer.toJson<int>(mtime),
    };
  }

  LoudnessData copyWith({
    String? path,
    Value<double?> lufs = const Value.absent(),
    int? mtime,
  }) => LoudnessData(
    path: path ?? this.path,
    lufs: lufs.present ? lufs.value : this.lufs,
    mtime: mtime ?? this.mtime,
  );
  LoudnessData copyWithCompanion(LoudnessCompanion data) {
    return LoudnessData(
      path: data.path.present ? data.path.value : this.path,
      lufs: data.lufs.present ? data.lufs.value : this.lufs,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LoudnessData(')
          ..write('path: $path, ')
          ..write('lufs: $lufs, ')
          ..write('mtime: $mtime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, lufs, mtime);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoudnessData &&
          other.path == this.path &&
          other.lufs == this.lufs &&
          other.mtime == this.mtime);
}

class LoudnessCompanion extends UpdateCompanion<LoudnessData> {
  final Value<String> path;
  final Value<double?> lufs;
  final Value<int> mtime;
  final Value<int> rowid;
  const LoudnessCompanion({
    this.path = const Value.absent(),
    this.lufs = const Value.absent(),
    this.mtime = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoudnessCompanion.insert({
    required String path,
    this.lufs = const Value.absent(),
    required int mtime,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       mtime = Value(mtime);
  static Insertable<LoudnessData> custom({
    Expression<String>? path,
    Expression<double>? lufs,
    Expression<int>? mtime,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (lufs != null) 'lufs': lufs,
      if (mtime != null) 'mtime': mtime,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoudnessCompanion copyWith({
    Value<String>? path,
    Value<double?>? lufs,
    Value<int>? mtime,
    Value<int>? rowid,
  }) {
    return LoudnessCompanion(
      path: path ?? this.path,
      lufs: lufs ?? this.lufs,
      mtime: mtime ?? this.mtime,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (lufs.present) {
      map['lufs'] = Variable<double>(lufs.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<int>(mtime.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoudnessCompanion(')
          ..write('path: $path, ')
          ..write('lufs: $lufs, ')
          ..write('mtime: $mtime, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountRowsTable extends AccountRows
    with TableInfo<$AccountRowsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseMeta = const VerificationMeta('base');
  @override
  late final GeneratedColumn<String> base = GeneratedColumn<String>(
    'base',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userMeta = const VerificationMeta('user');
  @override
  late final GeneratedColumn<String> user = GeneratedColumn<String>(
    'user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, type, name, base, user, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base')) {
      context.handle(
        _baseMeta,
        base.isAcceptableOrUnknown(data['base']!, _baseMeta),
      );
    } else if (isInserting) {
      context.missing(_baseMeta);
    }
    if (data.containsKey('user')) {
      context.handle(
        _userMeta,
        user.isAcceptableOrUnknown(data['user']!, _userMeta),
      );
    } else if (isInserting) {
      context.missing(_userMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      base: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base'],
      )!,
      user: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $AccountRowsTable createAlias(String alias) {
    return $AccountRowsTable(attachedDatabase, alias);
  }
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String id;
  final String type;
  final String name;
  final String base;
  final String user;
  final int position;
  const AccountRow({
    required this.id,
    required this.type,
    required this.name,
    required this.base,
    required this.user,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    map['base'] = Variable<String>(base);
    map['user'] = Variable<String>(user);
    map['position'] = Variable<int>(position);
    return map;
  }

  AccountRowsCompanion toCompanion(bool nullToAbsent) {
    return AccountRowsCompanion(
      id: Value(id),
      type: Value(type),
      name: Value(name),
      base: Value(base),
      user: Value(user),
      position: Value(position),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      base: serializer.fromJson<String>(json['base']),
      user: serializer.fromJson<String>(json['user']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'base': serializer.toJson<String>(base),
      'user': serializer.toJson<String>(user),
      'position': serializer.toJson<int>(position),
    };
  }

  AccountRow copyWith({
    String? id,
    String? type,
    String? name,
    String? base,
    String? user,
    int? position,
  }) => AccountRow(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    base: base ?? this.base,
    user: user ?? this.user,
    position: position ?? this.position,
  );
  AccountRow copyWithCompanion(AccountRowsCompanion data) {
    return AccountRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      base: data.base.present ? data.base.value : this.base,
      user: data.user.present ? data.user.value : this.user,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('base: $base, ')
          ..write('user: $user, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, name, base, user, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.base == this.base &&
          other.user == this.user &&
          other.position == this.position);
}

class AccountRowsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> name;
  final Value<String> base;
  final Value<String> user;
  final Value<int> position;
  final Value<int> rowid;
  const AccountRowsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.base = const Value.absent(),
    this.user = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountRowsCompanion.insert({
    required String id,
    required String type,
    required String name,
    required String base,
    required String user,
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       name = Value(name),
       base = Value(base),
       user = Value(user),
       position = Value(position);
  static Insertable<AccountRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? base,
    Expression<String>? user,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (base != null) 'base': base,
      if (user != null) 'user': user,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String>? name,
    Value<String>? base,
    Value<String>? user,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return AccountRowsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      base: base ?? this.base,
      user: user ?? this.user,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (base.present) {
      map['base'] = Variable<String>(base.value);
    }
    if (user.present) {
      map['user'] = Variable<String>(user.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountRowsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('base: $base, ')
          ..write('user: $user, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineTable extends Offline with TableInfo<$OfflineTable, OfflineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackPathMeta = const VerificationMeta(
    'trackPath',
  );
  @override
  late final GeneratedColumn<String> trackPath = GeneratedColumn<String>(
    'track_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failuresMeta = const VerificationMeta(
    'failures',
  );
  @override
  late final GeneratedColumn<int> failures = GeneratedColumn<int>(
    'failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackPath,
    filePath,
    size,
    addedAt,
    reason,
    state,
    failures,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_path')) {
      context.handle(
        _trackPathMeta,
        trackPath.isAcceptableOrUnknown(data['track_path']!, _trackPathMeta),
      );
    } else if (isInserting) {
      context.missing(_trackPathMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('failures')) {
      context.handle(
        _failuresMeta,
        failures.isAcceptableOrUnknown(data['failures']!, _failuresMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackPath};
  @override
  OfflineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineRow(
      trackPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_path'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      failures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failures'],
      )!,
    );
  }

  @override
  $OfflineTable createAlias(String alias) {
    return $OfflineTable(attachedDatabase, alias);
  }
}

class OfflineRow extends DataClass implements Insertable<OfflineRow> {
  final String trackPath;
  final String? filePath;
  final int size;
  final int addedAt;
  final String reason;
  final String state;
  final int failures;
  const OfflineRow({
    required this.trackPath,
    this.filePath,
    required this.size,
    required this.addedAt,
    required this.reason,
    required this.state,
    required this.failures,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_path'] = Variable<String>(trackPath);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    map['size'] = Variable<int>(size);
    map['added_at'] = Variable<int>(addedAt);
    map['reason'] = Variable<String>(reason);
    map['state'] = Variable<String>(state);
    map['failures'] = Variable<int>(failures);
    return map;
  }

  OfflineCompanion toCompanion(bool nullToAbsent) {
    return OfflineCompanion(
      trackPath: Value(trackPath),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      size: Value(size),
      addedAt: Value(addedAt),
      reason: Value(reason),
      state: Value(state),
      failures: Value(failures),
    );
  }

  factory OfflineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineRow(
      trackPath: serializer.fromJson<String>(json['trackPath']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      size: serializer.fromJson<int>(json['size']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      reason: serializer.fromJson<String>(json['reason']),
      state: serializer.fromJson<String>(json['state']),
      failures: serializer.fromJson<int>(json['failures']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackPath': serializer.toJson<String>(trackPath),
      'filePath': serializer.toJson<String?>(filePath),
      'size': serializer.toJson<int>(size),
      'addedAt': serializer.toJson<int>(addedAt),
      'reason': serializer.toJson<String>(reason),
      'state': serializer.toJson<String>(state),
      'failures': serializer.toJson<int>(failures),
    };
  }

  OfflineRow copyWith({
    String? trackPath,
    Value<String?> filePath = const Value.absent(),
    int? size,
    int? addedAt,
    String? reason,
    String? state,
    int? failures,
  }) => OfflineRow(
    trackPath: trackPath ?? this.trackPath,
    filePath: filePath.present ? filePath.value : this.filePath,
    size: size ?? this.size,
    addedAt: addedAt ?? this.addedAt,
    reason: reason ?? this.reason,
    state: state ?? this.state,
    failures: failures ?? this.failures,
  );
  OfflineRow copyWithCompanion(OfflineCompanion data) {
    return OfflineRow(
      trackPath: data.trackPath.present ? data.trackPath.value : this.trackPath,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      size: data.size.present ? data.size.value : this.size,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      reason: data.reason.present ? data.reason.value : this.reason,
      state: data.state.present ? data.state.value : this.state,
      failures: data.failures.present ? data.failures.value : this.failures,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineRow(')
          ..write('trackPath: $trackPath, ')
          ..write('filePath: $filePath, ')
          ..write('size: $size, ')
          ..write('addedAt: $addedAt, ')
          ..write('reason: $reason, ')
          ..write('state: $state, ')
          ..write('failures: $failures')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(trackPath, filePath, size, addedAt, reason, state, failures);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineRow &&
          other.trackPath == this.trackPath &&
          other.filePath == this.filePath &&
          other.size == this.size &&
          other.addedAt == this.addedAt &&
          other.reason == this.reason &&
          other.state == this.state &&
          other.failures == this.failures);
}

class OfflineCompanion extends UpdateCompanion<OfflineRow> {
  final Value<String> trackPath;
  final Value<String?> filePath;
  final Value<int> size;
  final Value<int> addedAt;
  final Value<String> reason;
  final Value<String> state;
  final Value<int> failures;
  final Value<int> rowid;
  const OfflineCompanion({
    this.trackPath = const Value.absent(),
    this.filePath = const Value.absent(),
    this.size = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.reason = const Value.absent(),
    this.state = const Value.absent(),
    this.failures = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineCompanion.insert({
    required String trackPath,
    this.filePath = const Value.absent(),
    this.size = const Value.absent(),
    required int addedAt,
    required String reason,
    required String state,
    this.failures = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackPath = Value(trackPath),
       addedAt = Value(addedAt),
       reason = Value(reason),
       state = Value(state);
  static Insertable<OfflineRow> custom({
    Expression<String>? trackPath,
    Expression<String>? filePath,
    Expression<int>? size,
    Expression<int>? addedAt,
    Expression<String>? reason,
    Expression<String>? state,
    Expression<int>? failures,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackPath != null) 'track_path': trackPath,
      if (filePath != null) 'file_path': filePath,
      if (size != null) 'size': size,
      if (addedAt != null) 'added_at': addedAt,
      if (reason != null) 'reason': reason,
      if (state != null) 'state': state,
      if (failures != null) 'failures': failures,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineCompanion copyWith({
    Value<String>? trackPath,
    Value<String?>? filePath,
    Value<int>? size,
    Value<int>? addedAt,
    Value<String>? reason,
    Value<String>? state,
    Value<int>? failures,
    Value<int>? rowid,
  }) {
    return OfflineCompanion(
      trackPath: trackPath ?? this.trackPath,
      filePath: filePath ?? this.filePath,
      size: size ?? this.size,
      addedAt: addedAt ?? this.addedAt,
      reason: reason ?? this.reason,
      state: state ?? this.state,
      failures: failures ?? this.failures,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackPath.present) {
      map['track_path'] = Variable<String>(trackPath.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (failures.present) {
      map['failures'] = Variable<int>(failures.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCompanion(')
          ..write('trackPath: $trackPath, ')
          ..write('filePath: $filePath, ')
          ..write('size: $size, ')
          ..write('addedAt: $addedAt, ')
          ..write('reason: $reason, ')
          ..write('state: $state, ')
          ..write('failures: $failures, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingScrobblesTable extends PendingScrobbles
    with TableInfo<$PendingScrobblesTable, PendingScrobble> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingScrobblesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<int> at = GeneratedColumn<int>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, accountId, remoteId, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_scrobbles';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingScrobble> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingScrobble map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingScrobble(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $PendingScrobblesTable createAlias(String alias) {
    return $PendingScrobblesTable(attachedDatabase, alias);
  }
}

class PendingScrobble extends DataClass implements Insertable<PendingScrobble> {
  final int id;
  final String accountId;
  final String remoteId;
  final int at;
  const PendingScrobble({
    required this.id,
    required this.accountId,
    required this.remoteId,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['remote_id'] = Variable<String>(remoteId);
    map['at'] = Variable<int>(at);
    return map;
  }

  PendingScrobblesCompanion toCompanion(bool nullToAbsent) {
    return PendingScrobblesCompanion(
      id: Value(id),
      accountId: Value(accountId),
      remoteId: Value(remoteId),
      at: Value(at),
    );
  }

  factory PendingScrobble.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingScrobble(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      at: serializer.fromJson<int>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<String>(accountId),
      'remoteId': serializer.toJson<String>(remoteId),
      'at': serializer.toJson<int>(at),
    };
  }

  PendingScrobble copyWith({
    int? id,
    String? accountId,
    String? remoteId,
    int? at,
  }) => PendingScrobble(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    remoteId: remoteId ?? this.remoteId,
    at: at ?? this.at,
  );
  PendingScrobble copyWithCompanion(PendingScrobblesCompanion data) {
    return PendingScrobble(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingScrobble(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, accountId, remoteId, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingScrobble &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.remoteId == this.remoteId &&
          other.at == this.at);
}

class PendingScrobblesCompanion extends UpdateCompanion<PendingScrobble> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> remoteId;
  final Value<int> at;
  const PendingScrobblesCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.at = const Value.absent(),
  });
  PendingScrobblesCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String remoteId,
    required int at,
  }) : accountId = Value(accountId),
       remoteId = Value(remoteId),
       at = Value(at);
  static Insertable<PendingScrobble> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? remoteId,
    Expression<int>? at,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (remoteId != null) 'remote_id': remoteId,
      if (at != null) 'at': at,
    });
  }

  PendingScrobblesCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? remoteId,
    Value<int>? at,
  }) {
    return PendingScrobblesCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      remoteId: remoteId ?? this.remoteId,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingScrobblesCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

class $AutoKeepBlocksTable extends AutoKeepBlocks
    with TableInfo<$AutoKeepBlocksTable, AutoKeepBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AutoKeepBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackPathMeta = const VerificationMeta(
    'trackPath',
  );
  @override
  late final GeneratedColumn<String> trackPath = GeneratedColumn<String>(
    'track_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [trackPath];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'auto_keep_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<AutoKeepBlock> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_path')) {
      context.handle(
        _trackPathMeta,
        trackPath.isAcceptableOrUnknown(data['track_path']!, _trackPathMeta),
      );
    } else if (isInserting) {
      context.missing(_trackPathMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackPath};
  @override
  AutoKeepBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AutoKeepBlock(
      trackPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_path'],
      )!,
    );
  }

  @override
  $AutoKeepBlocksTable createAlias(String alias) {
    return $AutoKeepBlocksTable(attachedDatabase, alias);
  }
}

class AutoKeepBlock extends DataClass implements Insertable<AutoKeepBlock> {
  final String trackPath;
  const AutoKeepBlock({required this.trackPath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_path'] = Variable<String>(trackPath);
    return map;
  }

  AutoKeepBlocksCompanion toCompanion(bool nullToAbsent) {
    return AutoKeepBlocksCompanion(trackPath: Value(trackPath));
  }

  factory AutoKeepBlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AutoKeepBlock(
      trackPath: serializer.fromJson<String>(json['trackPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'trackPath': serializer.toJson<String>(trackPath)};
  }

  AutoKeepBlock copyWith({String? trackPath}) =>
      AutoKeepBlock(trackPath: trackPath ?? this.trackPath);
  AutoKeepBlock copyWithCompanion(AutoKeepBlocksCompanion data) {
    return AutoKeepBlock(
      trackPath: data.trackPath.present ? data.trackPath.value : this.trackPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AutoKeepBlock(')
          ..write('trackPath: $trackPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => trackPath.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AutoKeepBlock && other.trackPath == this.trackPath);
}

class AutoKeepBlocksCompanion extends UpdateCompanion<AutoKeepBlock> {
  final Value<String> trackPath;
  final Value<int> rowid;
  const AutoKeepBlocksCompanion({
    this.trackPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AutoKeepBlocksCompanion.insert({
    required String trackPath,
    this.rowid = const Value.absent(),
  }) : trackPath = Value(trackPath);
  static Insertable<AutoKeepBlock> custom({
    Expression<String>? trackPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackPath != null) 'track_path': trackPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AutoKeepBlocksCompanion copyWith({
    Value<String>? trackPath,
    Value<int>? rowid,
  }) {
    return AutoKeepBlocksCompanion(
      trackPath: trackPath ?? this.trackPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackPath.present) {
      map['track_path'] = Variable<String>(trackPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AutoKeepBlocksCompanion(')
          ..write('trackPath: $trackPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, PlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, remoteId, name, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, remoteId};
  @override
  PlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class PlaylistRow extends DataClass implements Insertable<PlaylistRow> {
  final String accountId;
  final String remoteId;
  final String name;
  final int position;
  const PlaylistRow({
    required this.accountId,
    required this.remoteId,
    required this.name,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['remote_id'] = Variable<String>(remoteId);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      accountId: Value(accountId),
      remoteId: Value(remoteId),
      name: Value(name),
      position: Value(position),
    );
  }

  factory PlaylistRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'remoteId': serializer.toJson<String>(remoteId),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
    };
  }

  PlaylistRow copyWith({
    String? accountId,
    String? remoteId,
    String? name,
    int? position,
  }) => PlaylistRow(
    accountId: accountId ?? this.accountId,
    remoteId: remoteId ?? this.remoteId,
    name: name ?? this.name,
    position: position ?? this.position,
  );
  PlaylistRow copyWithCompanion(PlaylistsCompanion data) {
    return PlaylistRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRow(')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('name: $name, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, remoteId, name, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRow &&
          other.accountId == this.accountId &&
          other.remoteId == this.remoteId &&
          other.name == this.name &&
          other.position == this.position);
}

class PlaylistsCompanion extends UpdateCompanion<PlaylistRow> {
  final Value<String> accountId;
  final Value<String> remoteId;
  final Value<String> name;
  final Value<int> position;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.accountId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String accountId,
    required String remoteId,
    required String name,
    required int position,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       remoteId = Value(remoteId),
       name = Value(name),
       position = Value(position);
  static Insertable<PlaylistRow> custom({
    Expression<String>? accountId,
    Expression<String>? remoteId,
    Expression<String>? name,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (remoteId != null) 'remote_id': remoteId,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? remoteId,
    Value<String>? name,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      accountId: accountId ?? this.accountId,
      remoteId: remoteId ?? this.remoteId,
      name: name ?? this.name,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistItemsTable extends PlaylistItems
    with TableInfo<$PlaylistItemsTable, PlaylistItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
    'index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackPathMeta = const VerificationMeta(
    'trackPath',
  );
  @override
  late final GeneratedColumn<String> trackPath = GeneratedColumn<String>(
    'track_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    playlistId,
    index,
    trackPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('index')) {
      context.handle(
        _indexMeta,
        index.isAcceptableOrUnknown(data['index']!, _indexMeta),
      );
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    if (data.containsKey('track_path')) {
      context.handle(
        _trackPathMeta,
        trackPath.isAcceptableOrUnknown(data['track_path']!, _trackPathMeta),
      );
    } else if (isInserting) {
      context.missing(_trackPathMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, playlistId, index};
  @override
  PlaylistItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistItemRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      index: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}index'],
      )!,
      trackPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_path'],
      )!,
    );
  }

  @override
  $PlaylistItemsTable createAlias(String alias) {
    return $PlaylistItemsTable(attachedDatabase, alias);
  }
}

class PlaylistItemRow extends DataClass implements Insertable<PlaylistItemRow> {
  final String accountId;
  final String playlistId;
  final int index;
  final String trackPath;
  const PlaylistItemRow({
    required this.accountId,
    required this.playlistId,
    required this.index,
    required this.trackPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['playlist_id'] = Variable<String>(playlistId);
    map['index'] = Variable<int>(index);
    map['track_path'] = Variable<String>(trackPath);
    return map;
  }

  PlaylistItemsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistItemsCompanion(
      accountId: Value(accountId),
      playlistId: Value(playlistId),
      index: Value(index),
      trackPath: Value(trackPath),
    );
  }

  factory PlaylistItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistItemRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      index: serializer.fromJson<int>(json['index']),
      trackPath: serializer.fromJson<String>(json['trackPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'playlistId': serializer.toJson<String>(playlistId),
      'index': serializer.toJson<int>(index),
      'trackPath': serializer.toJson<String>(trackPath),
    };
  }

  PlaylistItemRow copyWith({
    String? accountId,
    String? playlistId,
    int? index,
    String? trackPath,
  }) => PlaylistItemRow(
    accountId: accountId ?? this.accountId,
    playlistId: playlistId ?? this.playlistId,
    index: index ?? this.index,
    trackPath: trackPath ?? this.trackPath,
  );
  PlaylistItemRow copyWithCompanion(PlaylistItemsCompanion data) {
    return PlaylistItemRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      index: data.index.present ? data.index.value : this.index,
      trackPath: data.trackPath.present ? data.trackPath.value : this.trackPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemRow(')
          ..write('accountId: $accountId, ')
          ..write('playlistId: $playlistId, ')
          ..write('index: $index, ')
          ..write('trackPath: $trackPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, playlistId, index, trackPath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistItemRow &&
          other.accountId == this.accountId &&
          other.playlistId == this.playlistId &&
          other.index == this.index &&
          other.trackPath == this.trackPath);
}

class PlaylistItemsCompanion extends UpdateCompanion<PlaylistItemRow> {
  final Value<String> accountId;
  final Value<String> playlistId;
  final Value<int> index;
  final Value<String> trackPath;
  final Value<int> rowid;
  const PlaylistItemsCompanion({
    this.accountId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.index = const Value.absent(),
    this.trackPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistItemsCompanion.insert({
    required String accountId,
    required String playlistId,
    required int index,
    required String trackPath,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       playlistId = Value(playlistId),
       index = Value(index),
       trackPath = Value(trackPath);
  static Insertable<PlaylistItemRow> custom({
    Expression<String>? accountId,
    Expression<String>? playlistId,
    Expression<int>? index,
    Expression<String>? trackPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (index != null) 'index': index,
      if (trackPath != null) 'track_path': trackPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistItemsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? playlistId,
    Value<int>? index,
    Value<String>? trackPath,
    Value<int>? rowid,
  }) {
    return PlaylistItemsCompanion(
      accountId: accountId ?? this.accountId,
      playlistId: playlistId ?? this.playlistId,
      index: index ?? this.index,
      trackPath: trackPath ?? this.trackPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (trackPath.present) {
      map['track_path'] = Variable<String>(trackPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('playlistId: $playlistId, ')
          ..write('index: $index, ')
          ..write('trackPath: $trackPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeptPlaylistsTable extends KeptPlaylists
    with TableInfo<$KeptPlaylistsTable, KeptPlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeptPlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, playlistId, fileName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kept_playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeptPlaylistRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, playlistId};
  @override
  KeptPlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeptPlaylistRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
    );
  }

  @override
  $KeptPlaylistsTable createAlias(String alias) {
    return $KeptPlaylistsTable(attachedDatabase, alias);
  }
}

class KeptPlaylistRow extends DataClass implements Insertable<KeptPlaylistRow> {
  final String accountId;
  final String playlistId;
  final String fileName;
  const KeptPlaylistRow({
    required this.accountId,
    required this.playlistId,
    required this.fileName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['playlist_id'] = Variable<String>(playlistId);
    map['file_name'] = Variable<String>(fileName);
    return map;
  }

  KeptPlaylistsCompanion toCompanion(bool nullToAbsent) {
    return KeptPlaylistsCompanion(
      accountId: Value(accountId),
      playlistId: Value(playlistId),
      fileName: Value(fileName),
    );
  }

  factory KeptPlaylistRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeptPlaylistRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      fileName: serializer.fromJson<String>(json['fileName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'playlistId': serializer.toJson<String>(playlistId),
      'fileName': serializer.toJson<String>(fileName),
    };
  }

  KeptPlaylistRow copyWith({
    String? accountId,
    String? playlistId,
    String? fileName,
  }) => KeptPlaylistRow(
    accountId: accountId ?? this.accountId,
    playlistId: playlistId ?? this.playlistId,
    fileName: fileName ?? this.fileName,
  );
  KeptPlaylistRow copyWithCompanion(KeptPlaylistsCompanion data) {
    return KeptPlaylistRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeptPlaylistRow(')
          ..write('accountId: $accountId, ')
          ..write('playlistId: $playlistId, ')
          ..write('fileName: $fileName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, playlistId, fileName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeptPlaylistRow &&
          other.accountId == this.accountId &&
          other.playlistId == this.playlistId &&
          other.fileName == this.fileName);
}

class KeptPlaylistsCompanion extends UpdateCompanion<KeptPlaylistRow> {
  final Value<String> accountId;
  final Value<String> playlistId;
  final Value<String> fileName;
  final Value<int> rowid;
  const KeptPlaylistsCompanion({
    this.accountId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeptPlaylistsCompanion.insert({
    required String accountId,
    required String playlistId,
    required String fileName,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       playlistId = Value(playlistId),
       fileName = Value(fileName);
  static Insertable<KeptPlaylistRow> custom({
    Expression<String>? accountId,
    Expression<String>? playlistId,
    Expression<String>? fileName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (fileName != null) 'file_name': fileName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeptPlaylistsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? playlistId,
    Value<String>? fileName,
    Value<int>? rowid,
  }) {
    return KeptPlaylistsCompanion(
      accountId: accountId ?? this.accountId,
      playlistId: playlistId ?? this.playlistId,
      fileName: fileName ?? this.fileName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeptPlaylistsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('playlistId: $playlistId, ')
          ..write('fileName: $fileName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDb extends GeneratedDatabase {
  _$LibraryDb(QueryExecutor e) : super(e);
  $LibraryDbManager get managers => $LibraryDbManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlayCountsTable playCounts = $PlayCountsTable(this);
  late final $LoudnessTable loudness = $LoudnessTable(this);
  late final $AccountRowsTable accountRows = $AccountRowsTable(this);
  late final $OfflineTable offline = $OfflineTable(this);
  late final $PendingScrobblesTable pendingScrobbles = $PendingScrobblesTable(
    this,
  );
  late final $AutoKeepBlocksTable autoKeepBlocks = $AutoKeepBlocksTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistItemsTable playlistItems = $PlaylistItemsTable(this);
  late final $KeptPlaylistsTable keptPlaylists = $KeptPlaylistsTable(this);
  late final Index tracksMergeKey = Index(
    'tracks_merge_key',
    'CREATE INDEX tracks_merge_key ON tracks (merge_key)',
  );
  late final Index tracksAlbumMergeKey = Index(
    'tracks_album_merge_key',
    'CREATE INDEX tracks_album_merge_key ON tracks (album_merge_key)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    playCounts,
    loudness,
    accountRows,
    offline,
    pendingScrobbles,
    autoKeepBlocks,
    playlists,
    playlistItems,
    keptPlaylists,
    tracksMergeKey,
    tracksAlbumMergeKey,
  ];
}

typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  required String path,
  Value<int> folderId,
  Value<String> accountId,
  Value<String> remoteId,
  Value<String> albumArtist,
  Value<int?> disc,
  Value<String?> coverId,
  Value<String?> suffix,
  Value<double?> replayGain,
  required String title,
  required String artist,
  required String album,
  required String albumKey,
  Value<String> genre,
  Value<int?> trackNo,
  required int durationMs,
  required bool hasCover,
  Value<int> mtime,
  required int size,
  Value<bool> missing,
  Value<bool> toRepair,
  required String searchKey,
  Value<String> mergeKey,
  Value<String> albumMergeKey,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<int> id,
  Value<String> path,
  Value<int> folderId,
  Value<String> accountId,
  Value<String> remoteId,
  Value<String> albumArtist,
  Value<int?> disc,
  Value<String?> coverId,
  Value<String?> suffix,
  Value<double?> replayGain,
  Value<String> title,
  Value<String> artist,
  Value<String> album,
  Value<String> albumKey,
  Value<String> genre,
  Value<int?> trackNo,
  Value<int> durationMs,
  Value<bool> hasCover,
  Value<int> mtime,
  Value<int> size,
  Value<bool> missing,
  Value<bool> toRepair,
  Value<String> searchKey,
  Value<String> mergeKey,
  Value<String> albumMergeKey,
});

class $$TracksTableFilterComposer extends Composer<_$LibraryDb, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disc => $composableBuilder(
    column: $table.disc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverId => $composableBuilder(
    column: $table.coverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get replayGain => $composableBuilder(
    column: $table.replayGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumKey => $composableBuilder(
    column: $table.albumKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNo => $composableBuilder(
    column: $table.trackNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasCover => $composableBuilder(
    column: $table.hasCover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get toRepair => $composableBuilder(
    column: $table.toRepair,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchKey => $composableBuilder(
    column: $table.searchKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mergeKey => $composableBuilder(
    column: $table.mergeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumMergeKey => $composableBuilder(
    column: $table.albumMergeKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$LibraryDb, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disc => $composableBuilder(
    column: $table.disc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverId => $composableBuilder(
    column: $table.coverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get replayGain => $composableBuilder(
    column: $table.replayGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumKey => $composableBuilder(
    column: $table.albumKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNo => $composableBuilder(
    column: $table.trackNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasCover => $composableBuilder(
    column: $table.hasCover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get toRepair => $composableBuilder(
    column: $table.toRepair,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchKey => $composableBuilder(
    column: $table.searchKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mergeKey => $composableBuilder(
    column: $table.mergeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumMergeKey => $composableBuilder(
    column: $table.albumMergeKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$LibraryDb, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => column,
  );

  GeneratedColumn<int> get disc =>
      $composableBuilder(column: $table.disc, builder: (column) => column);

  GeneratedColumn<String> get coverId =>
      $composableBuilder(column: $table.coverId, builder: (column) => column);

  GeneratedColumn<String> get suffix =>
      $composableBuilder(column: $table.suffix, builder: (column) => column);

  GeneratedColumn<double> get replayGain => $composableBuilder(
    column: $table.replayGain,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumKey =>
      $composableBuilder(column: $table.albumKey, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get trackNo =>
      $composableBuilder(column: $table.trackNo, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasCover =>
      $composableBuilder(column: $table.hasCover, builder: (column) => column);

  GeneratedColumn<int> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<bool> get missing =>
      $composableBuilder(column: $table.missing, builder: (column) => column);

  GeneratedColumn<bool> get toRepair =>
      $composableBuilder(column: $table.toRepair, builder: (column) => column);

  GeneratedColumn<String> get searchKey =>
      $composableBuilder(column: $table.searchKey, builder: (column) => column);

  GeneratedColumn<String> get mergeKey =>
      $composableBuilder(column: $table.mergeKey, builder: (column) => column);

  GeneratedColumn<String> get albumMergeKey => $composableBuilder(
    column: $table.albumMergeKey,
    builder: (column) => column,
  );
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $TracksTable,
          TrackRow,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (TrackRow, BaseReferences<_$LibraryDb, $TracksTable, TrackRow>),
          TrackRow,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$LibraryDb db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> folderId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> albumArtist = const Value.absent(),
                Value<int?> disc = const Value.absent(),
                Value<String?> coverId = const Value.absent(),
                Value<String?> suffix = const Value.absent(),
                Value<double?> replayGain = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String> albumKey = const Value.absent(),
                Value<String> genre = const Value.absent(),
                Value<int?> trackNo = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> hasCover = const Value.absent(),
                Value<int> mtime = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<bool> missing = const Value.absent(),
                Value<bool> toRepair = const Value.absent(),
                Value<String> searchKey = const Value.absent(),
                Value<String> mergeKey = const Value.absent(),
                Value<String> albumMergeKey = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                path: path,
                folderId: folderId,
                accountId: accountId,
                remoteId: remoteId,
                albumArtist: albumArtist,
                disc: disc,
                coverId: coverId,
                suffix: suffix,
                replayGain: replayGain,
                title: title,
                artist: artist,
                album: album,
                albumKey: albumKey,
                genre: genre,
                trackNo: trackNo,
                durationMs: durationMs,
                hasCover: hasCover,
                mtime: mtime,
                size: size,
                missing: missing,
                toRepair: toRepair,
                searchKey: searchKey,
                mergeKey: mergeKey,
                albumMergeKey: albumMergeKey,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String path,
                Value<int> folderId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> albumArtist = const Value.absent(),
                Value<int?> disc = const Value.absent(),
                Value<String?> coverId = const Value.absent(),
                Value<String?> suffix = const Value.absent(),
                Value<double?> replayGain = const Value.absent(),
                required String title,
                required String artist,
                required String album,
                required String albumKey,
                Value<String> genre = const Value.absent(),
                Value<int?> trackNo = const Value.absent(),
                required int durationMs,
                required bool hasCover,
                Value<int> mtime = const Value.absent(),
                required int size,
                Value<bool> missing = const Value.absent(),
                Value<bool> toRepair = const Value.absent(),
                required String searchKey,
                Value<String> mergeKey = const Value.absent(),
                Value<String> albumMergeKey = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                path: path,
                folderId: folderId,
                accountId: accountId,
                remoteId: remoteId,
                albumArtist: albumArtist,
                disc: disc,
                coverId: coverId,
                suffix: suffix,
                replayGain: replayGain,
                title: title,
                artist: artist,
                album: album,
                albumKey: albumKey,
                genre: genre,
                trackNo: trackNo,
                durationMs: durationMs,
                hasCover: hasCover,
                mtime: mtime,
                size: size,
                missing: missing,
                toRepair: toRepair,
                searchKey: searchKey,
                mergeKey: mergeKey,
                albumMergeKey: albumMergeKey,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TracksTable, TrackRow>(table),
                  BaseReferences<_$LibraryDb, $TracksTable, TrackRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $TracksTable,
      TrackRow,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (TrackRow, BaseReferences<_$LibraryDb, $TracksTable, TrackRow>),
      TrackRow,
      PrefetchHooks Function()
    >;
typedef $$PlayCountsTableCreateCompanionBuilder = PlayCountsCompanion Function({
  required String path,
  required int count,
  Value<int> imported,
  required int lastPlayed,
  Value<int> rowid,
});
typedef $$PlayCountsTableUpdateCompanionBuilder = PlayCountsCompanion Function({
  Value<String> path,
  Value<int> count,
  Value<int> imported,
  Value<int> lastPlayed,
  Value<int> rowid,
});

class $$PlayCountsTableFilterComposer
    extends Composer<_$LibraryDb, $PlayCountsTable> {
  $$PlayCountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imported => $composableBuilder(
    column: $table.imported,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayCountsTableOrderingComposer
    extends Composer<_$LibraryDb, $PlayCountsTable> {
  $$PlayCountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imported => $composableBuilder(
    column: $table.imported,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayCountsTableAnnotationComposer
    extends Composer<_$LibraryDb, $PlayCountsTable> {
  $$PlayCountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<int> get imported =>
      $composableBuilder(column: $table.imported, builder: (column) => column);

  GeneratedColumn<int> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => column,
  );
}

class $$PlayCountsTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $PlayCountsTable,
          PlayCount,
          $$PlayCountsTableFilterComposer,
          $$PlayCountsTableOrderingComposer,
          $$PlayCountsTableAnnotationComposer,
          $$PlayCountsTableCreateCompanionBuilder,
          $$PlayCountsTableUpdateCompanionBuilder,
          (PlayCount, BaseReferences<_$LibraryDb, $PlayCountsTable, PlayCount>),
          PlayCount,
          PrefetchHooks Function()
        > {
  $$PlayCountsTableTableManager(_$LibraryDb db, $PlayCountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayCountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayCountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayCountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<int> imported = const Value.absent(),
                Value<int> lastPlayed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayCountsCompanion(
                path: path,
                count: count,
                imported: imported,
                lastPlayed: lastPlayed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required int count,
                Value<int> imported = const Value.absent(),
                required int lastPlayed,
                Value<int> rowid = const Value.absent(),
              }) => PlayCountsCompanion.insert(
                path: path,
                count: count,
                imported: imported,
                lastPlayed: lastPlayed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayCountsTable, PlayCount>(table),
                  BaseReferences<_$LibraryDb, $PlayCountsTable, PlayCount>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayCountsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $PlayCountsTable,
      PlayCount,
      $$PlayCountsTableFilterComposer,
      $$PlayCountsTableOrderingComposer,
      $$PlayCountsTableAnnotationComposer,
      $$PlayCountsTableCreateCompanionBuilder,
      $$PlayCountsTableUpdateCompanionBuilder,
      (PlayCount, BaseReferences<_$LibraryDb, $PlayCountsTable, PlayCount>),
      PlayCount,
      PrefetchHooks Function()
    >;
typedef $$LoudnessTableCreateCompanionBuilder = LoudnessCompanion Function({
  required String path,
  Value<double?> lufs,
  required int mtime,
  Value<int> rowid,
});
typedef $$LoudnessTableUpdateCompanionBuilder = LoudnessCompanion Function({
  Value<String> path,
  Value<double?> lufs,
  Value<int> mtime,
  Value<int> rowid,
});

class $$LoudnessTableFilterComposer
    extends Composer<_$LibraryDb, $LoudnessTable> {
  $$LoudnessTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lufs => $composableBuilder(
    column: $table.lufs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LoudnessTableOrderingComposer
    extends Composer<_$LibraryDb, $LoudnessTable> {
  $$LoudnessTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lufs => $composableBuilder(
    column: $table.lufs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LoudnessTableAnnotationComposer
    extends Composer<_$LibraryDb, $LoudnessTable> {
  $$LoudnessTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<double> get lufs =>
      $composableBuilder(column: $table.lufs, builder: (column) => column);

  GeneratedColumn<int> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);
}

class $$LoudnessTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $LoudnessTable,
          LoudnessData,
          $$LoudnessTableFilterComposer,
          $$LoudnessTableOrderingComposer,
          $$LoudnessTableAnnotationComposer,
          $$LoudnessTableCreateCompanionBuilder,
          $$LoudnessTableUpdateCompanionBuilder,
          (
            LoudnessData,
            BaseReferences<_$LibraryDb, $LoudnessTable, LoudnessData>,
          ),
          LoudnessData,
          PrefetchHooks Function()
        > {
  $$LoudnessTableTableManager(_$LibraryDb db, $LoudnessTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoudnessTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoudnessTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoudnessTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<double?> lufs = const Value.absent(),
                Value<int> mtime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoudnessCompanion(
                path: path,
                lufs: lufs,
                mtime: mtime,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                Value<double?> lufs = const Value.absent(),
                required int mtime,
                Value<int> rowid = const Value.absent(),
              }) => LoudnessCompanion.insert(
                path: path,
                lufs: lufs,
                mtime: mtime,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LoudnessTable, LoudnessData>(table),
                  BaseReferences<_$LibraryDb, $LoudnessTable, LoudnessData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LoudnessTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $LoudnessTable,
      LoudnessData,
      $$LoudnessTableFilterComposer,
      $$LoudnessTableOrderingComposer,
      $$LoudnessTableAnnotationComposer,
      $$LoudnessTableCreateCompanionBuilder,
      $$LoudnessTableUpdateCompanionBuilder,
      (LoudnessData, BaseReferences<_$LibraryDb, $LoudnessTable, LoudnessData>),
      LoudnessData,
      PrefetchHooks Function()
    >;
typedef $$AccountRowsTableCreateCompanionBuilder =
    AccountRowsCompanion Function({
      required String id,
      required String type,
      required String name,
      required String base,
      required String user,
      required int position,
      Value<int> rowid,
    });
typedef $$AccountRowsTableUpdateCompanionBuilder =
    AccountRowsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String> name,
      Value<String> base,
      Value<String> user,
      Value<int> position,
      Value<int> rowid,
    });

class $$AccountRowsTableFilterComposer
    extends Composer<_$LibraryDb, $AccountRowsTable> {
  $$AccountRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get base => $composableBuilder(
    column: $table.base,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get user => $composableBuilder(
    column: $table.user,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountRowsTableOrderingComposer
    extends Composer<_$LibraryDb, $AccountRowsTable> {
  $$AccountRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get base => $composableBuilder(
    column: $table.base,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get user => $composableBuilder(
    column: $table.user,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountRowsTableAnnotationComposer
    extends Composer<_$LibraryDb, $AccountRowsTable> {
  $$AccountRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get base =>
      $composableBuilder(column: $table.base, builder: (column) => column);

  GeneratedColumn<String> get user =>
      $composableBuilder(column: $table.user, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$AccountRowsTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $AccountRowsTable,
          AccountRow,
          $$AccountRowsTableFilterComposer,
          $$AccountRowsTableOrderingComposer,
          $$AccountRowsTableAnnotationComposer,
          $$AccountRowsTableCreateCompanionBuilder,
          $$AccountRowsTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$LibraryDb, $AccountRowsTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountRowsTableTableManager(_$LibraryDb db, $AccountRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> base = const Value.absent(),
                Value<String> user = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountRowsCompanion(
                id: id,
                type: type,
                name: name,
                base: base,
                user: user,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                required String name,
                required String base,
                required String user,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => AccountRowsCompanion.insert(
                id: id,
                type: type,
                name: name,
                base: base,
                user: user,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountRowsTable, AccountRow>(table),
                  BaseReferences<_$LibraryDb, $AccountRowsTable, AccountRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $AccountRowsTable,
      AccountRow,
      $$AccountRowsTableFilterComposer,
      $$AccountRowsTableOrderingComposer,
      $$AccountRowsTableAnnotationComposer,
      $$AccountRowsTableCreateCompanionBuilder,
      $$AccountRowsTableUpdateCompanionBuilder,
      (AccountRow, BaseReferences<_$LibraryDb, $AccountRowsTable, AccountRow>),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineTableCreateCompanionBuilder = OfflineCompanion Function({
  required String trackPath,
  Value<String?> filePath,
  Value<int> size,
  required int addedAt,
  required String reason,
  required String state,
  Value<int> failures,
  Value<int> rowid,
});
typedef $$OfflineTableUpdateCompanionBuilder = OfflineCompanion Function({
  Value<String> trackPath,
  Value<String?> filePath,
  Value<int> size,
  Value<int> addedAt,
  Value<String> reason,
  Value<String> state,
  Value<int> failures,
  Value<int> rowid,
});

class $$OfflineTableFilterComposer
    extends Composer<_$LibraryDb, $OfflineTable> {
  $$OfflineTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineTableOrderingComposer
    extends Composer<_$LibraryDb, $OfflineTable> {
  $$OfflineTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineTableAnnotationComposer
    extends Composer<_$LibraryDb, $OfflineTable> {
  $$OfflineTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackPath =>
      $composableBuilder(column: $table.trackPath, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get failures =>
      $composableBuilder(column: $table.failures, builder: (column) => column);
}

class $$OfflineTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $OfflineTable,
          OfflineRow,
          $$OfflineTableFilterComposer,
          $$OfflineTableOrderingComposer,
          $$OfflineTableAnnotationComposer,
          $$OfflineTableCreateCompanionBuilder,
          $$OfflineTableUpdateCompanionBuilder,
          (OfflineRow, BaseReferences<_$LibraryDb, $OfflineTable, OfflineRow>),
          OfflineRow,
          PrefetchHooks Function()
        > {
  $$OfflineTableTableManager(_$LibraryDb db, $OfflineTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackPath = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> failures = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCompanion(
                trackPath: trackPath,
                filePath: filePath,
                size: size,
                addedAt: addedAt,
                reason: reason,
                state: state,
                failures: failures,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackPath,
                Value<String?> filePath = const Value.absent(),
                Value<int> size = const Value.absent(),
                required int addedAt,
                required String reason,
                required String state,
                Value<int> failures = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCompanion.insert(
                trackPath: trackPath,
                filePath: filePath,
                size: size,
                addedAt: addedAt,
                reason: reason,
                state: state,
                failures: failures,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineTable, OfflineRow>(table),
                  BaseReferences<_$LibraryDb, $OfflineTable, OfflineRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $OfflineTable,
      OfflineRow,
      $$OfflineTableFilterComposer,
      $$OfflineTableOrderingComposer,
      $$OfflineTableAnnotationComposer,
      $$OfflineTableCreateCompanionBuilder,
      $$OfflineTableUpdateCompanionBuilder,
      (OfflineRow, BaseReferences<_$LibraryDb, $OfflineTable, OfflineRow>),
      OfflineRow,
      PrefetchHooks Function()
    >;
typedef $$PendingScrobblesTableCreateCompanionBuilder =
    PendingScrobblesCompanion Function({
      Value<int> id,
      required String accountId,
      required String remoteId,
      required int at,
    });
typedef $$PendingScrobblesTableUpdateCompanionBuilder =
    PendingScrobblesCompanion Function({
      Value<int> id,
      Value<String> accountId,
      Value<String> remoteId,
      Value<int> at,
    });

class $$PendingScrobblesTableFilterComposer
    extends Composer<_$LibraryDb, $PendingScrobblesTable> {
  $$PendingScrobblesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingScrobblesTableOrderingComposer
    extends Composer<_$LibraryDb, $PendingScrobblesTable> {
  $$PendingScrobblesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingScrobblesTableAnnotationComposer
    extends Composer<_$LibraryDb, $PendingScrobblesTable> {
  $$PendingScrobblesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$PendingScrobblesTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $PendingScrobblesTable,
          PendingScrobble,
          $$PendingScrobblesTableFilterComposer,
          $$PendingScrobblesTableOrderingComposer,
          $$PendingScrobblesTableAnnotationComposer,
          $$PendingScrobblesTableCreateCompanionBuilder,
          $$PendingScrobblesTableUpdateCompanionBuilder,
          (
            PendingScrobble,
            BaseReferences<
              _$LibraryDb,
              $PendingScrobblesTable,
              PendingScrobble
            >,
          ),
          PendingScrobble,
          PrefetchHooks Function()
        > {
  $$PendingScrobblesTableTableManager(
    _$LibraryDb db,
    $PendingScrobblesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingScrobblesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingScrobblesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingScrobblesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<int> at = const Value.absent(),
              }) => PendingScrobblesCompanion(
                id: id,
                accountId: accountId,
                remoteId: remoteId,
                at: at,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String remoteId,
                required int at,
              }) => PendingScrobblesCompanion.insert(
                id: id,
                accountId: accountId,
                remoteId: remoteId,
                at: at,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingScrobblesTable, PendingScrobble>(table),
                  BaseReferences<
                    _$LibraryDb,
                    $PendingScrobblesTable,
                    PendingScrobble
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingScrobblesTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $PendingScrobblesTable,
      PendingScrobble,
      $$PendingScrobblesTableFilterComposer,
      $$PendingScrobblesTableOrderingComposer,
      $$PendingScrobblesTableAnnotationComposer,
      $$PendingScrobblesTableCreateCompanionBuilder,
      $$PendingScrobblesTableUpdateCompanionBuilder,
      (
        PendingScrobble,
        BaseReferences<_$LibraryDb, $PendingScrobblesTable, PendingScrobble>,
      ),
      PendingScrobble,
      PrefetchHooks Function()
    >;
typedef $$AutoKeepBlocksTableCreateCompanionBuilder =
    AutoKeepBlocksCompanion Function({
      required String trackPath,
      Value<int> rowid,
    });
typedef $$AutoKeepBlocksTableUpdateCompanionBuilder =
    AutoKeepBlocksCompanion Function({
      Value<String> trackPath,
      Value<int> rowid,
    });

class $$AutoKeepBlocksTableFilterComposer
    extends Composer<_$LibraryDb, $AutoKeepBlocksTable> {
  $$AutoKeepBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AutoKeepBlocksTableOrderingComposer
    extends Composer<_$LibraryDb, $AutoKeepBlocksTable> {
  $$AutoKeepBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AutoKeepBlocksTableAnnotationComposer
    extends Composer<_$LibraryDb, $AutoKeepBlocksTable> {
  $$AutoKeepBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackPath =>
      $composableBuilder(column: $table.trackPath, builder: (column) => column);
}

class $$AutoKeepBlocksTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $AutoKeepBlocksTable,
          AutoKeepBlock,
          $$AutoKeepBlocksTableFilterComposer,
          $$AutoKeepBlocksTableOrderingComposer,
          $$AutoKeepBlocksTableAnnotationComposer,
          $$AutoKeepBlocksTableCreateCompanionBuilder,
          $$AutoKeepBlocksTableUpdateCompanionBuilder,
          (
            AutoKeepBlock,
            BaseReferences<_$LibraryDb, $AutoKeepBlocksTable, AutoKeepBlock>,
          ),
          AutoKeepBlock,
          PrefetchHooks Function()
        > {
  $$AutoKeepBlocksTableTableManager(_$LibraryDb db, $AutoKeepBlocksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AutoKeepBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AutoKeepBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AutoKeepBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> trackPath = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AutoKeepBlocksCompanion(trackPath: trackPath, rowid: rowid),
          createCompanionCallback:
              ({
                required String trackPath,
                Value<int> rowid = const Value.absent(),
              }) => AutoKeepBlocksCompanion.insert(
                trackPath: trackPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AutoKeepBlocksTable, AutoKeepBlock>(table),
                  BaseReferences<
                    _$LibraryDb,
                    $AutoKeepBlocksTable,
                    AutoKeepBlock
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AutoKeepBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $AutoKeepBlocksTable,
      AutoKeepBlock,
      $$AutoKeepBlocksTableFilterComposer,
      $$AutoKeepBlocksTableOrderingComposer,
      $$AutoKeepBlocksTableAnnotationComposer,
      $$AutoKeepBlocksTableCreateCompanionBuilder,
      $$AutoKeepBlocksTableUpdateCompanionBuilder,
      (
        AutoKeepBlock,
        BaseReferences<_$LibraryDb, $AutoKeepBlocksTable, AutoKeepBlock>,
      ),
      AutoKeepBlock,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  required String accountId,
  required String remoteId,
  required String name,
  required int position,
  Value<int> rowid,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<String> accountId,
  Value<String> remoteId,
  Value<String> name,
  Value<int> position,
  Value<int> rowid,
});

class $$PlaylistsTableFilterComposer
    extends Composer<_$LibraryDb, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$LibraryDb, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$LibraryDb, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $PlaylistsTable,
          PlaylistRow,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (
            PlaylistRow,
            BaseReferences<_$LibraryDb, $PlaylistsTable, PlaylistRow>,
          ),
          PlaylistRow,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$LibraryDb db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                accountId: accountId,
                remoteId: remoteId,
                name: name,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String remoteId,
                required String name,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                accountId: accountId,
                remoteId: remoteId,
                name: name,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTable, PlaylistRow>(table),
                  BaseReferences<_$LibraryDb, $PlaylistsTable, PlaylistRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $PlaylistsTable,
      PlaylistRow,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (PlaylistRow, BaseReferences<_$LibraryDb, $PlaylistsTable, PlaylistRow>),
      PlaylistRow,
      PrefetchHooks Function()
    >;
typedef $$PlaylistItemsTableCreateCompanionBuilder =
    PlaylistItemsCompanion Function({
      required String accountId,
      required String playlistId,
      required int index,
      required String trackPath,
      Value<int> rowid,
    });
typedef $$PlaylistItemsTableUpdateCompanionBuilder =
    PlaylistItemsCompanion Function({
      Value<String> accountId,
      Value<String> playlistId,
      Value<int> index,
      Value<String> trackPath,
      Value<int> rowid,
    });

class $$PlaylistItemsTableFilterComposer
    extends Composer<_$LibraryDb, $PlaylistItemsTable> {
  $$PlaylistItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistItemsTableOrderingComposer
    extends Composer<_$LibraryDb, $PlaylistItemsTable> {
  $$PlaylistItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackPath => $composableBuilder(
    column: $table.trackPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistItemsTableAnnotationComposer
    extends Composer<_$LibraryDb, $PlaylistItemsTable> {
  $$PlaylistItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<String> get trackPath =>
      $composableBuilder(column: $table.trackPath, builder: (column) => column);
}

class $$PlaylistItemsTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $PlaylistItemsTable,
          PlaylistItemRow,
          $$PlaylistItemsTableFilterComposer,
          $$PlaylistItemsTableOrderingComposer,
          $$PlaylistItemsTableAnnotationComposer,
          $$PlaylistItemsTableCreateCompanionBuilder,
          $$PlaylistItemsTableUpdateCompanionBuilder,
          (
            PlaylistItemRow,
            BaseReferences<_$LibraryDb, $PlaylistItemsTable, PlaylistItemRow>,
          ),
          PlaylistItemRow,
          PrefetchHooks Function()
        > {
  $$PlaylistItemsTableTableManager(_$LibraryDb db, $PlaylistItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<int> index = const Value.absent(),
                Value<String> trackPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsCompanion(
                accountId: accountId,
                playlistId: playlistId,
                index: index,
                trackPath: trackPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String playlistId,
                required int index,
                required String trackPath,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsCompanion.insert(
                accountId: accountId,
                playlistId: playlistId,
                index: index,
                trackPath: trackPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistItemsTable, PlaylistItemRow>(table),
                  BaseReferences<
                    _$LibraryDb,
                    $PlaylistItemsTable,
                    PlaylistItemRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $PlaylistItemsTable,
      PlaylistItemRow,
      $$PlaylistItemsTableFilterComposer,
      $$PlaylistItemsTableOrderingComposer,
      $$PlaylistItemsTableAnnotationComposer,
      $$PlaylistItemsTableCreateCompanionBuilder,
      $$PlaylistItemsTableUpdateCompanionBuilder,
      (
        PlaylistItemRow,
        BaseReferences<_$LibraryDb, $PlaylistItemsTable, PlaylistItemRow>,
      ),
      PlaylistItemRow,
      PrefetchHooks Function()
    >;
typedef $$KeptPlaylistsTableCreateCompanionBuilder =
    KeptPlaylistsCompanion Function({
      required String accountId,
      required String playlistId,
      required String fileName,
      Value<int> rowid,
    });
typedef $$KeptPlaylistsTableUpdateCompanionBuilder =
    KeptPlaylistsCompanion Function({
      Value<String> accountId,
      Value<String> playlistId,
      Value<String> fileName,
      Value<int> rowid,
    });

class $$KeptPlaylistsTableFilterComposer
    extends Composer<_$LibraryDb, $KeptPlaylistsTable> {
  $$KeptPlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeptPlaylistsTableOrderingComposer
    extends Composer<_$LibraryDb, $KeptPlaylistsTable> {
  $$KeptPlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeptPlaylistsTableAnnotationComposer
    extends Composer<_$LibraryDb, $KeptPlaylistsTable> {
  $$KeptPlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);
}

class $$KeptPlaylistsTableTableManager
    extends
        RootTableManager<
          _$LibraryDb,
          $KeptPlaylistsTable,
          KeptPlaylistRow,
          $$KeptPlaylistsTableFilterComposer,
          $$KeptPlaylistsTableOrderingComposer,
          $$KeptPlaylistsTableAnnotationComposer,
          $$KeptPlaylistsTableCreateCompanionBuilder,
          $$KeptPlaylistsTableUpdateCompanionBuilder,
          (
            KeptPlaylistRow,
            BaseReferences<_$LibraryDb, $KeptPlaylistsTable, KeptPlaylistRow>,
          ),
          KeptPlaylistRow,
          PrefetchHooks Function()
        > {
  $$KeptPlaylistsTableTableManager(_$LibraryDb db, $KeptPlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeptPlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeptPlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeptPlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeptPlaylistsCompanion(
                accountId: accountId,
                playlistId: playlistId,
                fileName: fileName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String playlistId,
                required String fileName,
                Value<int> rowid = const Value.absent(),
              }) => KeptPlaylistsCompanion.insert(
                accountId: accountId,
                playlistId: playlistId,
                fileName: fileName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeptPlaylistsTable, KeptPlaylistRow>(table),
                  BaseReferences<
                    _$LibraryDb,
                    $KeptPlaylistsTable,
                    KeptPlaylistRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeptPlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$LibraryDb,
      $KeptPlaylistsTable,
      KeptPlaylistRow,
      $$KeptPlaylistsTableFilterComposer,
      $$KeptPlaylistsTableOrderingComposer,
      $$KeptPlaylistsTableAnnotationComposer,
      $$KeptPlaylistsTableCreateCompanionBuilder,
      $$KeptPlaylistsTableUpdateCompanionBuilder,
      (
        KeptPlaylistRow,
        BaseReferences<_$LibraryDb, $KeptPlaylistsTable, KeptPlaylistRow>,
      ),
      KeptPlaylistRow,
      PrefetchHooks Function()
    >;

class $LibraryDbManager {
  final _$LibraryDb _db;
  $LibraryDbManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlayCountsTableTableManager get playCounts =>
      $$PlayCountsTableTableManager(_db, _db.playCounts);
  $$LoudnessTableTableManager get loudness =>
      $$LoudnessTableTableManager(_db, _db.loudness);
  $$AccountRowsTableTableManager get accountRows =>
      $$AccountRowsTableTableManager(_db, _db.accountRows);
  $$OfflineTableTableManager get offline =>
      $$OfflineTableTableManager(_db, _db.offline);
  $$PendingScrobblesTableTableManager get pendingScrobbles =>
      $$PendingScrobblesTableTableManager(_db, _db.pendingScrobbles);
  $$AutoKeepBlocksTableTableManager get autoKeepBlocks =>
      $$AutoKeepBlocksTableTableManager(_db, _db.autoKeepBlocks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistItemsTableTableManager get playlistItems =>
      $$PlaylistItemsTableTableManager(_db, _db.playlistItems);
  $$KeptPlaylistsTableTableManager get keptPlaylists =>
      $$KeptPlaylistsTableTableManager(_db, _db.keptPlaylists);
}
