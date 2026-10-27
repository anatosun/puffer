import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Server responses by kind (`track`, `album`, `artist`, `playlist`, `list`) and ID, stored as JSON for offline browsing.
class CachedItems extends Table {
  TextColumn get kind => text()();
  TextColumn get id => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kind, id};
}

/// A download a person made (or automatic downloads made) of a track, album, playlist or artist.
class Pins extends Table {
  TextColumn get kind => text()();
  TextColumn get itemId => text()();
  BoolColumn get automatic => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kind, itemId};
}

/// The tracks each pin holds. The number of rows per track is its reference count.
class PinTracks extends Table {
  TextColumn get pinKind => text()();
  TextColumn get pinItemId => text()();
  TextColumn get trackId => text()();

  @override
  Set<Column> get primaryKey => {pinKind, pinItemId, trackId};
}

// Stored by index: append new values at the end.
enum FileStatus { queued, downloading, complete, failed, paused, evicted }

/// One row per track file on disk or in transfer.
class TrackFiles extends Table {
  TextColumn get trackId => text()();
  IntColumn get status => intEnum<FileStatus>()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  TextColumn get path => text().nullable()();
  IntColumn get size => integer().nullable()();
  TextColumn get coverArt => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastPlayed => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {trackId};
}

@DriftDatabase(tables: [CachedItems, Pins, PinTracks, TrackFiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'puffer'));

  @override
  int get schemaVersion => 1;
}
