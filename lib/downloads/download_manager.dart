import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../data/subsonic/models.dart';
import 'download_settings.dart';
import 'transfer_backend.dart';

enum PinKind { track, album, playlist, artist }

/// Download state of a pinned item, aggregated over its tracks.
class PinState {
  const PinState({
    required this.pinned,
    this.automatic = false,
    this.total = 0,
    this.complete = 0,
    this.failed = 0,
    this.progress = 0,
    this.listing = false,
  });

  static const none = PinState(pinned: false);

  final bool pinned;
  final bool automatic;
  final int total;
  final int complete;
  final int failed;

  /// Sum of the progress of all tracks, between 0 and [total].
  final double progress;

  /// The tracks of the item are still being listed, so [total] is not known yet.
  final bool listing;

  /// Once its tracks are listed, a pinned container without tracks, such as an empty playlist, counts as complete.
  bool get isComplete => pinned && !listing && complete == total;
  bool get isPartial =>
      pinned && !isComplete && complete + failed == total && total > 0;
  bool get isDownloading => pinned && !isComplete && !isPartial;
  double get fraction => total == 0 ? 0 : progress / total;
}

typedef TrackResolver = Future<List<Track>> Function(PinKind kind, String id);
typedef UrlBuilder = Uri Function(Track track, DownloadQuality quality);
typedef ArtworkFetcher = Future<void> Function(String coverArt);

/// Keeps the track files on disk in line with the pins.
///
/// A person pins a track, album, playlist or artist. Each pin holds a set of tracks, and a track file stays on disk while at least one pin holds it.
class DownloadManager {
  DownloadManager({
    required this.db,
    required this.backend,
    required this.resolve,
    required this.urlFor,
    required this.settings,
    this.fetchArtwork,
  });

  final AppDatabase db;
  final TransferBackend backend;
  final TrackResolver resolve;
  final UrlBuilder urlFor;
  final DownloadSettings Function() settings;
  final ArtworkFetcher? fetchArtwork;

  StreamSubscription<TransferUpdate>? _subscription;

  /// Pins whose tracks are being listed; [_listingChanged] fires when the set changes.
  final _listing = <(PinKind, String)>{};
  final _listingChanged = StreamController<void>.broadcast();

  static const _directory = 'music';

  /// While true, new files stay queued in the database and are not handed to [backend].
  bool _held = false;

  Future<void> start() async {
    _subscription ??= backend.updates.listen(_onUpdate);
    await backend.start();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _listingChanged.close();
  }

  // ---------------------------------------------------------------- pins

  Future<void> pin(PinKind kind, String id, {bool automatic = false}) async {
    final existing = await _pin(kind, id);
    // A pin the person made stays theirs when automatic downloads pin the same item.
    final isAutomatic = existing == null
        ? automatic
        : existing.automatic && automatic;
    // The pin comes first, so the item shows as downloading while its tracks are listed.
    await db
        .into(db.pins)
        .insertOnConflictUpdate(
          PinsCompanion.insert(
            kind: kind.name,
            itemId: id,
            automatic: Value(isAutomatic),
            createdAt: existing?.createdAt ?? DateTime.now(),
          ),
        );
    _setListing((kind, id), listing: true);
    try {
      final List<Track> tracks;
      try {
        tracks = await resolve(kind, id);
      } catch (_) {
        // Without its tracks a new pin would never finish, so it goes again.
        if (existing == null) await unpin(kind, id);
        rethrow;
      }
      await _setPinTracks(kind, id, tracks, redownloadEvicted: !isAutomatic);
    } finally {
      _setListing((kind, id), listing: false);
    }
  }

  void _setListing((PinKind, String) key, {required bool listing}) {
    final changed = listing ? _listing.add(key) : _listing.remove(key);
    if (changed && !_listingChanged.isClosed) _listingChanged.add(null);
  }

  Future<void> unpin(PinKind kind, String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.pins,
      )..where((t) => t.kind.equals(kind.name) & t.itemId.equals(id))).go();
      await (db.delete(
            db.pinTracks,
          )..where((t) => t.pinKind.equals(kind.name) & t.pinItemId.equals(id)))
          .go();
    });
    await _releaseOrphans();
  }

  Future<Pin?> _pin(PinKind kind, String id) =>
      (db.select(db.pins)
            ..where((t) => t.kind.equals(kind.name) & t.itemId.equals(id)))
          .getSingleOrNull();

  Future<void> _setPinTracks(
    PinKind kind,
    String id,
    List<Track> tracks, {
    required bool redownloadEvicted,
  }) async {
    await db.transaction(() async {
      await (db.delete(
            db.pinTracks,
          )..where((t) => t.pinKind.equals(kind.name) & t.pinItemId.equals(id)))
          .go();
      await db.batch(
        (b) => b.insertAllOnConflictUpdate(db.pinTracks, [
          for (final t in tracks)
            PinTracksCompanion.insert(
              pinKind: kind.name,
              pinItemId: id,
              trackId: t.id,
            ),
        ]),
      );
    });
    await _ensureFiles(tracks, redownloadEvicted: redownloadEvicted);
    await _releaseOrphans();
  }

  /// Re-resolves every pinned album, playlist and artist, so added tracks are downloaded and removed tracks are released.
  Future<void> syncPins() async {
    final pins = await db.select(db.pins).get();
    for (final p in pins) {
      final kind = PinKind.values.byName(p.kind);
      try {
        final tracks = await resolve(kind, p.itemId);
        await _setPinTracks(
          kind,
          p.itemId,
          tracks,
          redownloadEvicted: !p.automatic,
        );
      } catch (_) {
        // The server is unreachable, the item is gone or its data is malformed; keep the current files and sync the other pins.
      }
    }
  }

  /// Pins every starred item automatically and unpins automatic pins whose item is no longer starred.
  Future<void> syncAutomatic(Starred starred) async {
    final wanted = <(PinKind, String)>{
      for (final t in starred.tracks) (PinKind.track, t.id),
      for (final a in starred.albums) (PinKind.album, a.id),
      for (final a in starred.artists) (PinKind.artist, a.id),
    };
    final automatic = await (db.select(
      db.pins,
    )..where((t) => t.automatic.equals(true))).get();
    for (final p in automatic) {
      final key = (PinKind.values.byName(p.kind), p.itemId);
      if (!wanted.contains(key)) await unpin(key.$1, key.$2);
    }
    for (final (kind, id) in wanted) {
      await pin(kind, id, automatic: true);
    }
  }

  // ---------------------------------------------------------------- files

  Future<void> _ensureFiles(
    List<Track> tracks, {
    required bool redownloadEvicted,
  }) async {
    final ids = tracks.map((t) => t.id).toList();
    final existing = {
      for (final f in await (db.select(
        db.trackFiles,
      )..where((t) => t.trackId.isIn(ids))).get())
        f.trackId: f,
    };
    final s = settings();
    for (final track in tracks) {
      final file = existing[track.id];
      final needed =
          file == null ||
          file.status == FileStatus.failed ||
          (redownloadEvicted && file.status == FileStatus.evicted);
      if (!needed) continue;
      await db
          .into(db.trackFiles)
          .insertOnConflictUpdate(
            TrackFilesCompanion.insert(
              trackId: track.id,
              status: FileStatus.queued,
              progress: const Value(0),
              coverArt: Value(track.coverArt),
              createdAt: DateTime.now(),
            ),
          );
      if (!_held) await _transfer(track, s);
      final art = track.coverArt;
      if (art != null && fetchArtwork != null) {
        unawaited(fetchArtwork!(art).catchError((_) {}));
      }
    }
  }

  Future<void> _transfer(Track track, DownloadSettings s) => backend.enqueue(
    id: track.id,
    url: urlFor(track, s.quality),
    directory: _directory,
    filename: '${track.id}.${s.quality.format ?? track.suffix}',
  );

  /// Holds back or releases the transfers, for "Download over cellular". Holding cancels the transfers in progress and keeps their files queued. Releasing hands every queued file to [backend] again, which also replaces transfers queued by an earlier version with a Wi-Fi constraint.
  Future<void> setHeld(bool held) async {
    _held = held;
    final rows =
        await (db.select(db.trackFiles)..where(
              (t) => held
                  ? t.status.isInValues([
                      FileStatus.queued,
                      FileStatus.downloading,
                      FileStatus.paused,
                    ])
                  : t.status.equalsValue(FileStatus.queued),
            ))
            .get();
    if (held) {
      for (final f in rows) {
        await backend.cancel(f.trackId);
      }
      await (db.update(
        db.trackFiles,
      )..where((t) => t.trackId.isIn(rows.map((f) => f.trackId)))).write(
        const TrackFilesCompanion(
          status: Value(FileStatus.queued),
          progress: Value(0),
        ),
      );
      return;
    }
    final s = settings();
    for (final track in await _cachedTracks(rows.map((f) => f.trackId))) {
      if (_held) return;
      await _transfer(track, s);
    }
  }

  /// Deletes every file that no pin holds.
  Future<void> _releaseOrphans() async {
    final orphans = await db
        .customSelect(
          'SELECT track_id, path FROM track_files WHERE track_id NOT IN (SELECT track_id FROM pin_tracks)',
          readsFrom: {db.trackFiles, db.pinTracks},
        )
        .get();
    for (final row in orphans) {
      await _deleteFile(
        row.read<String>('track_id'),
        row.readNullable<String>('path'),
      );
      await (db.delete(
        db.trackFiles,
      )..where((t) => t.trackId.equals(row.read<String>('track_id')))).go();
    }
  }

  Future<void> _deleteFile(String trackId, String? path) async {
    await backend.cancel(trackId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _onUpdate(TransferUpdate update) async {
    final row = await (db.select(
      db.trackFiles,
    )..where((t) => t.trackId.equals(update.id))).getSingleOrNull();
    if (row == null) return; // Released while in transfer.
    var companion = const TrackFilesCompanion();
    if (update.status != null) {
      companion = companion.copyWith(status: Value(update.status!));
    }
    if (update.progress != null) {
      companion = companion.copyWith(progress: Value(update.progress!));
    }
    if (update.status == FileStatus.complete && update.path != null) {
      final size = await File(update.path!).length();
      companion = companion.copyWith(
        path: Value(update.path),
        size: Value(size),
        progress: const Value(1),
      );
    }
    await (db.update(
      db.trackFiles,
    )..where((t) => t.trackId.equals(update.id))).write(companion);
    if (update.status == FileStatus.complete) await optimizeStorage();
  }

  Future<void> retryFailed() async {
    final failed = await (db.select(
      db.trackFiles,
    )..where((t) => t.status.equalsValue(FileStatus.failed))).get();
    if (failed.isEmpty) return;
    await _ensureFiles(
      await _cachedTracks(failed.map((f) => f.trackId)),
      redownloadEvicted: false,
    );
  }

  Future<List<Track>> _cachedTracks(Iterable<String> ids) async {
    final rows = await (db.select(
      db.cachedItems,
    )..where((t) => t.kind.equals('track') & t.id.isIn(ids))).get();
    return [for (final r in rows) Track(_decode(r.json))];
  }

  Future<void> markPlayed(String trackId) =>
      (db.update(db.trackFiles)..where((t) => t.trackId.equals(trackId))).write(
        TrackFilesCompanion(lastPlayed: Value(DateTime.now())),
      );

  /// When "Optimize Storage" is on and the downloads exceed the limit, deletes the least recently played files that only automatic pins hold.
  Future<void> optimizeStorage() async {
    final s = settings();
    if (!s.optimizeStorage) return;
    var total = await totalBytes();
    if (total <= s.storageLimitBytes) return;
    final candidates = await db
        .customSelect(
          '''
      SELECT f.track_id, f.path, f.size FROM track_files f
      WHERE f.status = ${FileStatus.complete.index}
        AND NOT EXISTS (
          SELECT 1 FROM pin_tracks pt JOIN pins p ON p.kind = pt.pin_kind AND p.item_id = pt.pin_item_id
          WHERE pt.track_id = f.track_id AND p.automatic = 0)
      ORDER BY COALESCE(f.last_played, f.created_at) ASC
      ''',
          readsFrom: {db.trackFiles, db.pinTracks, db.pins},
        )
        .get();
    for (final row in candidates) {
      if (total <= s.storageLimitBytes) break;
      final id = row.read<String>('track_id');
      await _deleteFile(id, row.readNullable<String>('path'));
      await (db.update(
        db.trackFiles,
      )..where((t) => t.trackId.equals(id))).write(
        const TrackFilesCompanion(
          status: Value(FileStatus.evicted),
          path: Value(null),
          progress: Value(0),
        ),
      );
      total -= row.readNullable<int>('size') ?? 0;
    }
  }

  Future<void> removeAll() async {
    final files = await db.select(db.trackFiles).get();
    for (final f in files) {
      await _deleteFile(f.trackId, f.path);
    }
    await db.transaction(() async {
      await db.delete(db.pinTracks).go();
      await db.delete(db.pins).go();
      await db.delete(db.trackFiles).go();
    });
  }

  // ---------------------------------------------------------------- queries

  Future<int> totalBytes() async {
    final sum = db.trackFiles.size.sum();
    final row =
        await (db.selectOnly(db.trackFiles)
              ..addColumns([sum])
              ..where(db.trackFiles.status.equalsValue(FileStatus.complete)))
            .getSingle();
    return row.read(sum) ?? 0;
  }

  Stream<TrackFile?> watchTrack(String trackId) => (db.select(
    db.trackFiles,
  )..where((t) => t.trackId.equals(trackId))).watchSingleOrNull();

  Future<String?> localPath(String trackId) async {
    final f = await (db.select(
      db.trackFiles,
    )..where((t) => t.trackId.equals(trackId))).getSingleOrNull();
    return f?.status == FileStatus.complete ? f!.path : null;
  }

  /// The state of a pin, from the database and from whether its tracks are still being listed.
  Stream<PinState> watchPin(PinKind kind, String id) {
    final key = (kind, id);
    PinState? latest;
    StreamSubscription<PinState>? rows;
    StreamSubscription<void>? listing;
    late final StreamController<PinState> out;
    void emit() {
      final s = latest;
      if (s == null) return;
      out.add(
        s.pinned
            ? PinState(
                pinned: true,
                automatic: s.automatic,
                total: s.total,
                complete: s.complete,
                failed: s.failed,
                progress: s.progress,
                listing: _listing.contains(key),
              )
            : s,
      );
    }

    out = StreamController<PinState>(
      onListen: () {
        rows = _watchPinRow(kind, id).listen((s) {
          latest = s;
          emit();
        }, onError: out.addError);
        listing = _listingChanged.stream.listen((_) => emit());
      },
      onCancel: () async {
        await rows?.cancel();
        await listing?.cancel();
      },
    );
    return out.stream;
  }

  Stream<PinState> _watchPinRow(PinKind kind, String id) {
    const complete = 2, failed = 3;
    assert(
      FileStatus.complete.index == complete &&
          FileStatus.failed.index == failed,
    );
    return db
        .customSelect(
          '''
          SELECT p.automatic AS automatic,
            COUNT(pt.track_id) AS total,
            SUM(CASE WHEN f.status = $complete THEN 1 ELSE 0 END) AS complete,
            SUM(CASE WHEN f.status = $failed THEN 1 ELSE 0 END) AS failed,
            SUM(COALESCE(f.progress, 0)) AS progress
          FROM pins p
          LEFT JOIN pin_tracks pt ON pt.pin_kind = p.kind AND pt.pin_item_id = p.item_id
          LEFT JOIN track_files f ON f.track_id = pt.track_id
          WHERE p.kind = ? AND p.item_id = ?
          GROUP BY p.kind, p.item_id
          ''',
          variables: [Variable.withString(kind.name), Variable.withString(id)],
          readsFrom: {db.pins, db.pinTracks, db.trackFiles},
        )
        .watchSingleOrNull()
        .map(
          (row) => row == null
              ? PinState.none
              : PinState(
                  pinned: true,
                  automatic: row.read<bool>('automatic'),
                  total: row.read<int>('total'),
                  complete: row.readNullable<int>('complete') ?? 0,
                  failed: row.readNullable<int>('failed') ?? 0,
                  progress: row.readNullable<double>('progress') ?? 0,
                ),
        );
  }

  /// IDs of all complete track files, most recently downloaded first.
  Stream<List<String>> watchCompleteTrackIds() =>
      (db.select(db.trackFiles)
            ..where((t) => t.status.equalsValue(FileStatus.complete))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => [for (final r in rows) r.trackId]);

  /// Track files not yet on disk: downloading first, then queued, paused and failed, each oldest first.
  Stream<List<TrackFile>> watchTransfers() {
    const order = [
      FileStatus.downloading,
      FileStatus.queued,
      FileStatus.paused,
      FileStatus.failed,
    ];
    return (db.select(db.trackFiles)
          ..where((t) => t.status.isInValues(order))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map(
          (rows) => rows
            ..sort(
              (a, b) =>
                  order.indexOf(a.status).compareTo(order.indexOf(b.status)),
            ),
        );
  }

  Stream<List<Pin>> watchPins(PinKind kind) =>
      (db.select(db.pins)..where((t) => t.kind.equals(kind.name))).watch();

  static Json _decode(String json) =>
      (jsonDecode(json) as Map).cast<String, dynamic>();
}
