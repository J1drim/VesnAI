// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $NoteRowsTable extends NoteRows with TableInfo<$NoteRowsTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Note'),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  static const VerificationMeta _linksJsonMeta = const VerificationMeta(
    'linksJson',
  );
  @override
  late final GeneratedColumn<String> linksJson = GeneratedColumn<String>(
    'links_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedMeta = const VerificationMeta(
    'updated',
  );
  @override
  late final GeneratedColumn<String> updated = GeneratedColumn<String>(
    'updated',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<String> doneAt = GeneratedColumn<String>(
    'done_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<int> syncState = GeneratedColumn<int>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    title,
    body,
    type,
    tagsJson,
    origin,
    linksJson,
    attachmentsJson,
    source,
    updated,
    version,
    done,
    doneAt,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
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
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('links_json')) {
      context.handle(
        _linksJsonMeta,
        linksJson.isAcceptableOrUnknown(data['links_json']!, _linksJsonMeta),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('updated')) {
      context.handle(
        _updatedMeta,
        updated.isAcceptableOrUnknown(data['updated']!, _updatedMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      linksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}links_json'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      updated: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}done_at'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $NoteRowsTable createAlias(String alias) {
    return $NoteRowsTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String path;
  final String title;
  final String body;
  final String type;
  final String tagsJson;
  final String origin;
  final String linksJson;
  final String attachmentsJson;
  final String source;
  final String updated;
  final int version;
  final bool done;
  final String doneAt;
  final int syncState;
  const NoteRow({
    required this.path,
    required this.title,
    required this.body,
    required this.type,
    required this.tagsJson,
    required this.origin,
    required this.linksJson,
    required this.attachmentsJson,
    required this.source,
    required this.updated,
    required this.version,
    required this.done,
    required this.doneAt,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['type'] = Variable<String>(type);
    map['tags_json'] = Variable<String>(tagsJson);
    map['origin'] = Variable<String>(origin);
    map['links_json'] = Variable<String>(linksJson);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['source'] = Variable<String>(source);
    map['updated'] = Variable<String>(updated);
    map['version'] = Variable<int>(version);
    map['done'] = Variable<bool>(done);
    map['done_at'] = Variable<String>(doneAt);
    map['sync_state'] = Variable<int>(syncState);
    return map;
  }

  NoteRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteRowsCompanion(
      path: Value(path),
      title: Value(title),
      body: Value(body),
      type: Value(type),
      tagsJson: Value(tagsJson),
      origin: Value(origin),
      linksJson: Value(linksJson),
      attachmentsJson: Value(attachmentsJson),
      source: Value(source),
      updated: Value(updated),
      version: Value(version),
      done: Value(done),
      doneAt: Value(doneAt),
      syncState: Value(syncState),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      type: serializer.fromJson<String>(json['type']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      origin: serializer.fromJson<String>(json['origin']),
      linksJson: serializer.fromJson<String>(json['linksJson']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      source: serializer.fromJson<String>(json['source']),
      updated: serializer.fromJson<String>(json['updated']),
      version: serializer.fromJson<int>(json['version']),
      done: serializer.fromJson<bool>(json['done']),
      doneAt: serializer.fromJson<String>(json['doneAt']),
      syncState: serializer.fromJson<int>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'type': serializer.toJson<String>(type),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'origin': serializer.toJson<String>(origin),
      'linksJson': serializer.toJson<String>(linksJson),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'source': serializer.toJson<String>(source),
      'updated': serializer.toJson<String>(updated),
      'version': serializer.toJson<int>(version),
      'done': serializer.toJson<bool>(done),
      'doneAt': serializer.toJson<String>(doneAt),
      'syncState': serializer.toJson<int>(syncState),
    };
  }

  NoteRow copyWith({
    String? path,
    String? title,
    String? body,
    String? type,
    String? tagsJson,
    String? origin,
    String? linksJson,
    String? attachmentsJson,
    String? source,
    String? updated,
    int? version,
    bool? done,
    String? doneAt,
    int? syncState,
  }) => NoteRow(
    path: path ?? this.path,
    title: title ?? this.title,
    body: body ?? this.body,
    type: type ?? this.type,
    tagsJson: tagsJson ?? this.tagsJson,
    origin: origin ?? this.origin,
    linksJson: linksJson ?? this.linksJson,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    source: source ?? this.source,
    updated: updated ?? this.updated,
    version: version ?? this.version,
    done: done ?? this.done,
    doneAt: doneAt ?? this.doneAt,
    syncState: syncState ?? this.syncState,
  );
  NoteRow copyWithCompanion(NoteRowsCompanion data) {
    return NoteRow(
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      type: data.type.present ? data.type.value : this.type,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      origin: data.origin.present ? data.origin.value : this.origin,
      linksJson: data.linksJson.present ? data.linksJson.value : this.linksJson,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      source: data.source.present ? data.source.value : this.source,
      updated: data.updated.present ? data.updated.value : this.updated,
      version: data.version.present ? data.version.value : this.version,
      done: data.done.present ? data.done.value : this.done,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('type: $type, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('origin: $origin, ')
          ..write('linksJson: $linksJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('source: $source, ')
          ..write('updated: $updated, ')
          ..write('version: $version, ')
          ..write('done: $done, ')
          ..write('doneAt: $doneAt, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    title,
    body,
    type,
    tagsJson,
    origin,
    linksJson,
    attachmentsJson,
    source,
    updated,
    version,
    done,
    doneAt,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.path == this.path &&
          other.title == this.title &&
          other.body == this.body &&
          other.type == this.type &&
          other.tagsJson == this.tagsJson &&
          other.origin == this.origin &&
          other.linksJson == this.linksJson &&
          other.attachmentsJson == this.attachmentsJson &&
          other.source == this.source &&
          other.updated == this.updated &&
          other.version == this.version &&
          other.done == this.done &&
          other.doneAt == this.doneAt &&
          other.syncState == this.syncState);
}

class NoteRowsCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> path;
  final Value<String> title;
  final Value<String> body;
  final Value<String> type;
  final Value<String> tagsJson;
  final Value<String> origin;
  final Value<String> linksJson;
  final Value<String> attachmentsJson;
  final Value<String> source;
  final Value<String> updated;
  final Value<int> version;
  final Value<bool> done;
  final Value<String> doneAt;
  final Value<int> syncState;
  final Value<int> rowid;
  const NoteRowsCompanion({
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.type = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.origin = const Value.absent(),
    this.linksJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.source = const Value.absent(),
    this.updated = const Value.absent(),
    this.version = const Value.absent(),
    this.done = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteRowsCompanion.insert({
    required String path,
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.type = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.origin = const Value.absent(),
    this.linksJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.source = const Value.absent(),
    this.updated = const Value.absent(),
    this.version = const Value.absent(),
    this.done = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path);
  static Insertable<NoteRow> custom({
    Expression<String>? path,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? type,
    Expression<String>? tagsJson,
    Expression<String>? origin,
    Expression<String>? linksJson,
    Expression<String>? attachmentsJson,
    Expression<String>? source,
    Expression<String>? updated,
    Expression<int>? version,
    Expression<bool>? done,
    Expression<String>? doneAt,
    Expression<int>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (type != null) 'type': type,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (origin != null) 'origin': origin,
      if (linksJson != null) 'links_json': linksJson,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (source != null) 'source': source,
      if (updated != null) 'updated': updated,
      if (version != null) 'version': version,
      if (done != null) 'done': done,
      if (doneAt != null) 'done_at': doneAt,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteRowsCompanion copyWith({
    Value<String>? path,
    Value<String>? title,
    Value<String>? body,
    Value<String>? type,
    Value<String>? tagsJson,
    Value<String>? origin,
    Value<String>? linksJson,
    Value<String>? attachmentsJson,
    Value<String>? source,
    Value<String>? updated,
    Value<int>? version,
    Value<bool>? done,
    Value<String>? doneAt,
    Value<int>? syncState,
    Value<int>? rowid,
  }) {
    return NoteRowsCompanion(
      path: path ?? this.path,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      tagsJson: tagsJson ?? this.tagsJson,
      origin: origin ?? this.origin,
      linksJson: linksJson ?? this.linksJson,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      source: source ?? this.source,
      updated: updated ?? this.updated,
      version: version ?? this.version,
      done: done ?? this.done,
      doneAt: doneAt ?? this.doneAt,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (linksJson.present) {
      map['links_json'] = Variable<String>(linksJson.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (updated.present) {
      map['updated'] = Variable<String>(updated.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<String>(doneAt.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteRowsCompanion(')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('type: $type, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('origin: $origin, ')
          ..write('linksJson: $linksJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('source: $source, ')
          ..write('updated: $updated, ')
          ..write('version: $version, ')
          ..write('done: $done, ')
          ..write('doneAt: $doneAt, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) =>
      SyncMetaData(key: key ?? this.key, value: value ?? this.value);
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionRowsTable extends ChatSessionRows
    with TableInfo<$ChatSessionRowsTable, ChatSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('New chat'),
  );
  static const VerificationMeta _createdMeta = const VerificationMeta(
    'created',
  );
  @override
  late final GeneratedColumn<String> created = GeneratedColumn<String>(
    'created',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedMeta = const VerificationMeta(
    'updated',
  );
  @override
  late final GeneratedColumn<String> updated = GeneratedColumn<String>(
    'updated',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<int> syncState = GeneratedColumn<int>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    created,
    updated,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_session_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('created')) {
      context.handle(
        _createdMeta,
        created.isAcceptableOrUnknown(data['created']!, _createdMeta),
      );
    }
    if (data.containsKey('updated')) {
      context.handle(
        _updatedMeta,
        updated.isAcceptableOrUnknown(data['updated']!, _updatedMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      created: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created'],
      )!,
      updated: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $ChatSessionRowsTable createAlias(String alias) {
    return $ChatSessionRowsTable(attachedDatabase, alias);
  }
}

class ChatSessionRow extends DataClass implements Insertable<ChatSessionRow> {
  final String id;
  final String title;
  final String created;
  final String updated;
  final int syncState;
  const ChatSessionRow({
    required this.id,
    required this.title,
    required this.created,
    required this.updated,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created'] = Variable<String>(created);
    map['updated'] = Variable<String>(updated);
    map['sync_state'] = Variable<int>(syncState);
    return map;
  }

  ChatSessionRowsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionRowsCompanion(
      id: Value(id),
      title: Value(title),
      created: Value(created),
      updated: Value(updated),
      syncState: Value(syncState),
    );
  }

  factory ChatSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSessionRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      created: serializer.fromJson<String>(json['created']),
      updated: serializer.fromJson<String>(json['updated']),
      syncState: serializer.fromJson<int>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'created': serializer.toJson<String>(created),
      'updated': serializer.toJson<String>(updated),
      'syncState': serializer.toJson<int>(syncState),
    };
  }

  ChatSessionRow copyWith({
    String? id,
    String? title,
    String? created,
    String? updated,
    int? syncState,
  }) => ChatSessionRow(
    id: id ?? this.id,
    title: title ?? this.title,
    created: created ?? this.created,
    updated: updated ?? this.updated,
    syncState: syncState ?? this.syncState,
  );
  ChatSessionRow copyWithCompanion(ChatSessionRowsCompanion data) {
    return ChatSessionRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      created: data.created.present ? data.created.value : this.created,
      updated: data.updated.present ? data.updated.value : this.updated,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, created, updated, syncState);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSessionRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.created == this.created &&
          other.updated == this.updated &&
          other.syncState == this.syncState);
}

class ChatSessionRowsCompanion extends UpdateCompanion<ChatSessionRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> created;
  final Value<String> updated;
  final Value<int> syncState;
  final Value<int> rowid;
  const ChatSessionRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatSessionRowsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<ChatSessionRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? created,
    Expression<String>? updated,
    Expression<int>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatSessionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? created,
    Value<String>? updated,
    Value<int>? syncState,
    Value<int>? rowid,
  }) {
    return ChatSessionRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (created.present) {
      map['created'] = Variable<String>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<String>(updated.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessageRowsTable extends ChatMessageRows
    with TableInfo<$ChatMessageRowsTable, ChatMessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessageRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<String> ts = GeneratedColumn<String>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ttsAudioPathMeta = const VerificationMeta(
    'ttsAudioPath',
  );
  @override
  late final GeneratedColumn<String> ttsAudioPath = GeneratedColumn<String>(
    'tts_audio_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<int> syncState = GeneratedColumn<int>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    role,
    content,
    ts,
    ttsAudioPath,
    attachmentsJson,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_message_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    }
    if (data.containsKey('tts_audio_path')) {
      context.handle(
        _ttsAudioPathMeta,
        ttsAudioPath.isAcceptableOrUnknown(
          data['tts_audio_path']!,
          _ttsAudioPathMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ts'],
      )!,
      ttsAudioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tts_audio_path'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $ChatMessageRowsTable createAlias(String alias) {
    return $ChatMessageRowsTable(attachedDatabase, alias);
  }
}

class ChatMessageRow extends DataClass implements Insertable<ChatMessageRow> {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String ts;
  final String ttsAudioPath;
  final String attachmentsJson;
  final int syncState;
  const ChatMessageRow({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.ts,
    required this.ttsAudioPath,
    required this.attachmentsJson,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['ts'] = Variable<String>(ts);
    map['tts_audio_path'] = Variable<String>(ttsAudioPath);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['sync_state'] = Variable<int>(syncState);
    return map;
  }

  ChatMessageRowsCompanion toCompanion(bool nullToAbsent) {
    return ChatMessageRowsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      ts: Value(ts),
      ttsAudioPath: Value(ttsAudioPath),
      attachmentsJson: Value(attachmentsJson),
      syncState: Value(syncState),
    );
  }

  factory ChatMessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessageRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      ts: serializer.fromJson<String>(json['ts']),
      ttsAudioPath: serializer.fromJson<String>(json['ttsAudioPath']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      syncState: serializer.fromJson<int>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'ts': serializer.toJson<String>(ts),
      'ttsAudioPath': serializer.toJson<String>(ttsAudioPath),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'syncState': serializer.toJson<int>(syncState),
    };
  }

  ChatMessageRow copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? content,
    String? ts,
    String? ttsAudioPath,
    String? attachmentsJson,
    int? syncState,
  }) => ChatMessageRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    role: role ?? this.role,
    content: content ?? this.content,
    ts: ts ?? this.ts,
    ttsAudioPath: ttsAudioPath ?? this.ttsAudioPath,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    syncState: syncState ?? this.syncState,
  );
  ChatMessageRow copyWithCompanion(ChatMessageRowsCompanion data) {
    return ChatMessageRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      ts: data.ts.present ? data.ts.value : this.ts,
      ttsAudioPath: data.ttsAudioPath.present
          ? data.ttsAudioPath.value
          : this.ttsAudioPath,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('ts: $ts, ')
          ..write('ttsAudioPath: $ttsAudioPath, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    content,
    ts,
    ttsAudioPath,
    attachmentsJson,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.ts == this.ts &&
          other.ttsAudioPath == this.ttsAudioPath &&
          other.attachmentsJson == this.attachmentsJson &&
          other.syncState == this.syncState);
}

class ChatMessageRowsCompanion extends UpdateCompanion<ChatMessageRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<String> ts;
  final Value<String> ttsAudioPath;
  final Value<String> attachmentsJson;
  final Value<int> syncState;
  final Value<int> rowid;
  const ChatMessageRowsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.ts = const Value.absent(),
    this.ttsAudioPath = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessageRowsCompanion.insert({
    required String id,
    required String sessionId,
    required String role,
    this.content = const Value.absent(),
    this.ts = const Value.absent(),
    this.ttsAudioPath = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       role = Value(role);
  static Insertable<ChatMessageRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? ts,
    Expression<String>? ttsAudioPath,
    Expression<String>? attachmentsJson,
    Expression<int>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (ts != null) 'ts': ts,
      if (ttsAudioPath != null) 'tts_audio_path': ttsAudioPath,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessageRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? role,
    Value<String>? content,
    Value<String>? ts,
    Value<String>? ttsAudioPath,
    Value<String>? attachmentsJson,
    Value<int>? syncState,
    Value<int>? rowid,
  }) {
    return ChatMessageRowsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      ts: ts ?? this.ts,
      ttsAudioPath: ttsAudioPath ?? this.ttsAudioPath,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (ts.present) {
      map['ts'] = Variable<String>(ts.value);
    }
    if (ttsAudioPath.present) {
      map['tts_audio_path'] = Variable<String>(ttsAudioPath.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageRowsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('ts: $ts, ')
          ..write('ttsAudioPath: $ttsAudioPath, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$VesnaiDatabase extends GeneratedDatabase {
  _$VesnaiDatabase(QueryExecutor e) : super(e);
  $VesnaiDatabaseManager get managers => $VesnaiDatabaseManager(this);
  late final $NoteRowsTable noteRows = $NoteRowsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $ChatSessionRowsTable chatSessionRows = $ChatSessionRowsTable(
    this,
  );
  late final $ChatMessageRowsTable chatMessageRows = $ChatMessageRowsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    noteRows,
    syncMeta,
    chatSessionRows,
    chatMessageRows,
  ];
}

typedef $$NoteRowsTableCreateCompanionBuilder =
    NoteRowsCompanion Function({
      required String path,
      Value<String> title,
      Value<String> body,
      Value<String> type,
      Value<String> tagsJson,
      Value<String> origin,
      Value<String> linksJson,
      Value<String> attachmentsJson,
      Value<String> source,
      Value<String> updated,
      Value<int> version,
      Value<bool> done,
      Value<String> doneAt,
      Value<int> syncState,
      Value<int> rowid,
    });
typedef $$NoteRowsTableUpdateCompanionBuilder =
    NoteRowsCompanion Function({
      Value<String> path,
      Value<String> title,
      Value<String> body,
      Value<String> type,
      Value<String> tagsJson,
      Value<String> origin,
      Value<String> linksJson,
      Value<String> attachmentsJson,
      Value<String> source,
      Value<String> updated,
      Value<int> version,
      Value<bool> done,
      Value<String> doneAt,
      Value<int> syncState,
      Value<int> rowid,
    });

class $$NoteRowsTableFilterComposer
    extends Composer<_$VesnaiDatabase, $NoteRowsTable> {
  $$NoteRowsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linksJson => $composableBuilder(
    column: $table.linksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updated => $composableBuilder(
    column: $table.updated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteRowsTableOrderingComposer
    extends Composer<_$VesnaiDatabase, $NoteRowsTable> {
  $$NoteRowsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linksJson => $composableBuilder(
    column: $table.linksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updated => $composableBuilder(
    column: $table.updated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteRowsTableAnnotationComposer
    extends Composer<_$VesnaiDatabase, $NoteRowsTable> {
  $$NoteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get linksJson =>
      $composableBuilder(column: $table.linksJson, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get updated =>
      $composableBuilder(column: $table.updated, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<String> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$NoteRowsTableTableManager
    extends
        RootTableManager<
          _$VesnaiDatabase,
          $NoteRowsTable,
          NoteRow,
          $$NoteRowsTableFilterComposer,
          $$NoteRowsTableOrderingComposer,
          $$NoteRowsTableAnnotationComposer,
          $$NoteRowsTableCreateCompanionBuilder,
          $$NoteRowsTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$VesnaiDatabase, $NoteRowsTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NoteRowsTableTableManager(_$VesnaiDatabase db, $NoteRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> linksJson = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> updated = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<String> doneAt = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion(
                path: path,
                title: title,
                body: body,
                type: type,
                tagsJson: tagsJson,
                origin: origin,
                linksJson: linksJson,
                attachmentsJson: attachmentsJson,
                source: source,
                updated: updated,
                version: version,
                done: done,
                doneAt: doneAt,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> linksJson = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> updated = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<String> doneAt = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion.insert(
                path: path,
                title: title,
                body: body,
                type: type,
                tagsJson: tagsJson,
                origin: origin,
                linksJson: linksJson,
                attachmentsJson: attachmentsJson,
                source: source,
                updated: updated,
                version: version,
                done: done,
                doneAt: doneAt,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$VesnaiDatabase,
      $NoteRowsTable,
      NoteRow,
      $$NoteRowsTableFilterComposer,
      $$NoteRowsTableOrderingComposer,
      $$NoteRowsTableAnnotationComposer,
      $$NoteRowsTableCreateCompanionBuilder,
      $$NoteRowsTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$VesnaiDatabase, $NoteRowsTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$VesnaiDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$VesnaiDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$VesnaiDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$VesnaiDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$VesnaiDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$VesnaiDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$VesnaiDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$VesnaiDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionRowsTableCreateCompanionBuilder =
    ChatSessionRowsCompanion Function({
      required String id,
      Value<String> title,
      Value<String> created,
      Value<String> updated,
      Value<int> syncState,
      Value<int> rowid,
    });
typedef $$ChatSessionRowsTableUpdateCompanionBuilder =
    ChatSessionRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> created,
      Value<String> updated,
      Value<int> syncState,
      Value<int> rowid,
    });

class $$ChatSessionRowsTableFilterComposer
    extends Composer<_$VesnaiDatabase, $ChatSessionRowsTable> {
  $$ChatSessionRowsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updated => $composableBuilder(
    column: $table.updated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionRowsTableOrderingComposer
    extends Composer<_$VesnaiDatabase, $ChatSessionRowsTable> {
  $$ChatSessionRowsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updated => $composableBuilder(
    column: $table.updated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionRowsTableAnnotationComposer
    extends Composer<_$VesnaiDatabase, $ChatSessionRowsTable> {
  $$ChatSessionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get created =>
      $composableBuilder(column: $table.created, builder: (column) => column);

  GeneratedColumn<String> get updated =>
      $composableBuilder(column: $table.updated, builder: (column) => column);

  GeneratedColumn<int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$ChatSessionRowsTableTableManager
    extends
        RootTableManager<
          _$VesnaiDatabase,
          $ChatSessionRowsTable,
          ChatSessionRow,
          $$ChatSessionRowsTableFilterComposer,
          $$ChatSessionRowsTableOrderingComposer,
          $$ChatSessionRowsTableAnnotationComposer,
          $$ChatSessionRowsTableCreateCompanionBuilder,
          $$ChatSessionRowsTableUpdateCompanionBuilder,
          (
            ChatSessionRow,
            BaseReferences<
              _$VesnaiDatabase,
              $ChatSessionRowsTable,
              ChatSessionRow
            >,
          ),
          ChatSessionRow,
          PrefetchHooks Function()
        > {
  $$ChatSessionRowsTableTableManager(
    _$VesnaiDatabase db,
    $ChatSessionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> created = const Value.absent(),
                Value<String> updated = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionRowsCompanion(
                id: id,
                title: title,
                created: created,
                updated: updated,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> created = const Value.absent(),
                Value<String> updated = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionRowsCompanion.insert(
                id: id,
                title: title,
                created: created,
                updated: updated,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$VesnaiDatabase,
      $ChatSessionRowsTable,
      ChatSessionRow,
      $$ChatSessionRowsTableFilterComposer,
      $$ChatSessionRowsTableOrderingComposer,
      $$ChatSessionRowsTableAnnotationComposer,
      $$ChatSessionRowsTableCreateCompanionBuilder,
      $$ChatSessionRowsTableUpdateCompanionBuilder,
      (
        ChatSessionRow,
        BaseReferences<_$VesnaiDatabase, $ChatSessionRowsTable, ChatSessionRow>,
      ),
      ChatSessionRow,
      PrefetchHooks Function()
    >;
typedef $$ChatMessageRowsTableCreateCompanionBuilder =
    ChatMessageRowsCompanion Function({
      required String id,
      required String sessionId,
      required String role,
      Value<String> content,
      Value<String> ts,
      Value<String> ttsAudioPath,
      Value<String> attachmentsJson,
      Value<int> syncState,
      Value<int> rowid,
    });
typedef $$ChatMessageRowsTableUpdateCompanionBuilder =
    ChatMessageRowsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> role,
      Value<String> content,
      Value<String> ts,
      Value<String> ttsAudioPath,
      Value<String> attachmentsJson,
      Value<int> syncState,
      Value<int> rowid,
    });

class $$ChatMessageRowsTableFilterComposer
    extends Composer<_$VesnaiDatabase, $ChatMessageRowsTable> {
  $$ChatMessageRowsTableFilterComposer({
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

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ttsAudioPath => $composableBuilder(
    column: $table.ttsAudioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessageRowsTableOrderingComposer
    extends Composer<_$VesnaiDatabase, $ChatMessageRowsTable> {
  $$ChatMessageRowsTableOrderingComposer({
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

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ttsAudioPath => $composableBuilder(
    column: $table.ttsAudioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessageRowsTableAnnotationComposer
    extends Composer<_$VesnaiDatabase, $ChatMessageRowsTable> {
  $$ChatMessageRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get ttsAudioPath => $composableBuilder(
    column: $table.ttsAudioPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$ChatMessageRowsTableTableManager
    extends
        RootTableManager<
          _$VesnaiDatabase,
          $ChatMessageRowsTable,
          ChatMessageRow,
          $$ChatMessageRowsTableFilterComposer,
          $$ChatMessageRowsTableOrderingComposer,
          $$ChatMessageRowsTableAnnotationComposer,
          $$ChatMessageRowsTableCreateCompanionBuilder,
          $$ChatMessageRowsTableUpdateCompanionBuilder,
          (
            ChatMessageRow,
            BaseReferences<
              _$VesnaiDatabase,
              $ChatMessageRowsTable,
              ChatMessageRow
            >,
          ),
          ChatMessageRow,
          PrefetchHooks Function()
        > {
  $$ChatMessageRowsTableTableManager(
    _$VesnaiDatabase db,
    $ChatMessageRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessageRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessageRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessageRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> ts = const Value.absent(),
                Value<String> ttsAudioPath = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessageRowsCompanion(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                ts: ts,
                ttsAudioPath: ttsAudioPath,
                attachmentsJson: attachmentsJson,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String role,
                Value<String> content = const Value.absent(),
                Value<String> ts = const Value.absent(),
                Value<String> ttsAudioPath = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessageRowsCompanion.insert(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                ts: ts,
                ttsAudioPath: ttsAudioPath,
                attachmentsJson: attachmentsJson,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessageRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$VesnaiDatabase,
      $ChatMessageRowsTable,
      ChatMessageRow,
      $$ChatMessageRowsTableFilterComposer,
      $$ChatMessageRowsTableOrderingComposer,
      $$ChatMessageRowsTableAnnotationComposer,
      $$ChatMessageRowsTableCreateCompanionBuilder,
      $$ChatMessageRowsTableUpdateCompanionBuilder,
      (
        ChatMessageRow,
        BaseReferences<_$VesnaiDatabase, $ChatMessageRowsTable, ChatMessageRow>,
      ),
      ChatMessageRow,
      PrefetchHooks Function()
    >;

class $VesnaiDatabaseManager {
  final _$VesnaiDatabase _db;
  $VesnaiDatabaseManager(this._db);
  $$NoteRowsTableTableManager get noteRows =>
      $$NoteRowsTableTableManager(_db, _db.noteRows);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$ChatSessionRowsTableTableManager get chatSessionRows =>
      $$ChatSessionRowsTableTableManager(_db, _db.chatSessionRows);
  $$ChatMessageRowsTableTableManager get chatMessageRows =>
      $$ChatMessageRowsTableTableManager(_db, _db.chatMessageRows);
}
