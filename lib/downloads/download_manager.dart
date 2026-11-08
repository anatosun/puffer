import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:path/path.dart' as p;

import '../data/db/database.dart';
import '../data/subsonic/models.dart';
import 'download_settings.dart';
import 'library_folder.dart';
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

  @override
  bool operator ==(Object other) =>
      other is PinState &&
      other.pinned == pinned &&
      other.automatic == automatic &&
      other.total == total &&
      other.complete == complete &&
      other.failed == failed &&
      other.progress == progress &&
      other.listing == listing;

  @override
  int get hashCode => Object.hash(
    pinned,
    automatic,
    total,
    complete,
    failed,
    progress,
    listing,
  );

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

/// The size a download of [track] in [quality] should reach: the file size for the original, and the bit rate times the duration for a transcoded stream.
int? expectedBytes(Track track, DownloadQuality quality) {
  final bitRate = quality.maxBitRate;
  if (bitRate == null) return track.size;
  final seconds = track.duration.inSeconds;
  return seconds == 0 ? null : bitRate * 1000 ~/ 8 * seconds;
}

typedef TrackResolver = Future<List<Track>> Function(PinKind kind, String id);

/// Where the file of a track in a quality comes from, and the extension it is saved with.
typedef DownloadSource = ({Uri url, String extension});
typedef UrlBuilder = Future<DownloadSource> Function(
  Track track,
  DownloadQuality quality,
);
typedef ArtworkFetcher = Future<void> Function(String coverArt);
typedef PlaylistReader = Future<Playlist?> Function(String id);

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
    this._folder,
    this.privateRoot,
    this.cachedPlaylist,
    this.appVersion = '',
  });

  final AppDatabase db;
  final TransferBackend backend;
  final TrackResolver resolve;
  final UrlBuilder urlFor;
  final DownloadSettings Function() settings;
  final ArtworkFetcher? fetchArtwork;

  /// The absolute path of the private store, where files go while no library folder is set; files move back there when the folder is turned off.
  final String? privateRoot;

  /// The cached playlist with its songs, for the playlist files of the library folder.
  final PlaylistReader? cachedPlaylist;

  /// The version of the app, written in the iTunes library.
  final String appVersion;

  /// The library folder: an absolute path where downloads are stored as `Music/Artist/Album/01 Title.flac`, with the playlist files in `Playlists`, or null for the private store.
  String? get folder => _folder;
  String? _folder;

  StreamSubscription<TransferUpdate>? _subscription;

  /// Pins whose tracks are being listed; [_listingChanged] fires when the set changes.
  final _listing = <(PinKind, String)>{};
  final _listingChanged = StreamController<void>.broadcast();

  static const _directory = 'music';

  /// While true, new files stay queued in the database and are not handed to [backend].
  bool _held = false;

  /// The updates of the transfers, applied one after the other, so two completed files never trim the storage at the same time.
  Future<void> _updates = Future.value();

  /// Completes once every transfer update received so far is applied.
  Future<void> get settled => _updates;

  Future<void> start() async {
    // A failed update leaves its file as it was, and the updates after it still apply.
    _subscription ??= backend.updates.listen(
      (update) => _updates = _updates
          .then((_) => _onUpdate(update))
          .catchError((Object _) {}),
    );
    await backend.start();
  }

  Future<void> dispose() async {
    _playlistTimer?.cancel();
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
      } catch (e) {
        // The server is unreachable, the item is gone or its data is malformed; keep the current files and sync the other pins. Only the type of the error is logged, since its text may hold a URL with credentials.
        debugPrint(
          'Sync of ${kind.name} pin ${p.itemId} failed: ${e.runtimeType}',
        );
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

  Future<void> _transfer(Track track, DownloadSettings s) async {
    final source = await urlFor(track, s.quality);
    final root = _folder;
    if (root == null) {
      await backend.enqueue(
        id: track.id,
        url: source.url,
        directory: _directory,
        filename: '${track.id}.${source.extension}',
        expectedBytes: expectedBytes(track, s.quality),
      );
      return;
    }
    // The path is kept from now on, so no other song takes the same name while this one downloads.
    final path = await _freePath(root, track, source.extension);
    await (db.update(db.trackFiles)..where((t) => t.trackId.equals(track.id)))
        .write(TrackFilesCompanion(path: Value(path)));
    await backend.enqueue(
      id: track.id,
      url: source.url,
      directory: p.dirname(path),
      filename: p.basename(path),
      absolute: true,
      expectedBytes: expectedBytes(track, s.quality),
    );
  }

  /// The path of [track] in the library folder [root], numbered when another song already has its name or a file Puffer did not write is there.
  Future<String> _freePath(String root, Track track, String extension) async {
    final relative = libraryPath(track, extension);
    for (var n = 1; ; n++) {
      final path = p.joinAll([root, ...numberedPath(relative, n).split('/')]);
      final owner = await (db.select(
        db.trackFiles,
      )..where((t) => t.path.equals(path))).getSingleOrNull();
      if (owner?.trackId == track.id) return path;
      if (owner == null && !await File(path).exists()) return path;
    }
  }

  /// Moves every downloaded file to the library folder [target], or back to the private store when it is null, and writes the playlist files there. Transfers in progress start again at the new place. Each file is moved and recorded on its own, so a move that fails half way leaves every file where the database says it is, and a second attempt finishes it.
  Future<void> moveTo(String? target) async {
    if (target == _folder) return;
    final privateRoot = this.privateRoot;
    if (target == null && privateRoot == null) {
      throw StateError('No private store to move the downloads back to');
    }
    await _arrange(target);
  }

  /// Moves the songs of the library folder to the paths of the current layout, for a folder written by an earlier version. Songs whose metadata is not cached stay where they are.
  Future<void> relayout() async {
    if (_folder == null) return;
    await _arrange(_folder, keepUncached: true);
  }

  Future<void> _arrange(String? target, {bool keepUncached = false}) async {
    final old = _folder;
    final wasHeld = _held;
    await setHeld(true);
    try {
      // Fails here, before anything moves, when the folder cannot be written.
      if (target != null) await Directory(target).create(recursive: true);
      final files = await db.select(db.trackFiles).get();
      final tracks = {
        for (final t in await _cachedTracks(files.map((f) => f.trackId)))
          t.id: t,
      };
      for (final f in files) {
        final from = f.path;
        if (f.status != FileStatus.complete) {
          // A path kept for a transfer that has not finished.
          if (from != null) {
            await (db.update(db.trackFiles)
                  ..where((t) => t.trackId.equals(f.trackId)))
                .write(const TrackFilesCompanion(path: Value(null)));
          }
          continue;
        }
        if (from == null || !await File(from).exists()) continue;
        if (keepUncached && !tracks.containsKey(f.trackId)) continue;
        final extension = p.extension(from).replaceFirst('.', '');
        final to = target == null
            ? p.join(privateRoot!, _directory, '${f.trackId}.$extension')
            : await _freePath(
                target,
                tracks[f.trackId] ??
                    Track({'id': f.trackId, 'title': f.trackId}),
                extension,
              );
        if (to == from) continue;
        await moveFile(from, to);
        await (db.update(db.trackFiles)
              ..where((t) => t.trackId.equals(f.trackId)))
            .write(TrackFilesCompanion(path: Value(to)));
        if (old != null) await pruneEmptyFolders(from, old);
      }
      if (old != null && old != target) {
        // Only the playlist files Puffer wrote go; anything else a person put in the old folder stays.
        await writePlaylistFiles(
          root: old,
          tracks: const [],
          playlists: const [],
          version: appVersion,
        );
      }
      _folder = target;
    } finally {
      if (!wasHeld) await setHeld(false);
    }
    await writePlaylists();
  }

  /// Rewrites the stored paths under [from] to the same paths under [to], for a folder that moved without its files moving: iOS gives the app a new container path on every update.
  Future<void> rebase(String from, String to) async {
    if (from == to) return;
    final rows = await (db.select(
      db.trackFiles,
    )..where((t) => t.path.like('$from%'))).get();
    for (final f in rows) {
      final path = f.path!;
      if (!p.isWithin(from, path)) continue;
      await (db.update(
        db.trackFiles,
      )..where((t) => t.trackId.equals(f.trackId))).write(
        TrackFilesCompanion(
          path: Value(p.join(to, p.relative(path, from: from))),
        ),
      );
    }
  }

  /// The playlist files are written a moment after the last change, so a whole album finishing writes them once.
  static const playlistDelay = Duration(seconds: 3);
  Timer? _playlistTimer;
  Future<void> _playlistWrites = Future.value();

  void _schedulePlaylists() {
    if (_folder == null) return;
    _playlistTimer?.cancel();
    _playlistTimer = Timer(playlistDelay, () => unawaited(writePlaylists()));
  }

  /// Writes the M3U8 file of every downloaded playlist and the iTunes library of every downloaded song into the library folder. Songs whose file is not there yet are left out until it is.
  Future<void> writePlaylists() => _playlistWrites = _playlistWrites
      .then((_) => _writePlaylists())
      .catchError((Object e) {
        // A folder that went away or refuses a file, such as Android refusing XML in Music; the songs stay playable. The type alone is logged, as the text holds paths.
        debugPrint('Writing the playlist files failed: ${e.runtimeType}');
      });

  Future<void> _writePlaylists() async {
    final root = _folder;
    if (root == null) return;
    final files = await (db.select(
      db.trackFiles,
    )..where((t) => t.status.equalsValue(FileStatus.complete))).get();
    final tracks = {
      for (final t in await _cachedTracks(files.map((f) => f.trackId))) t.id: t,
    };
    final inFolder = <FolderTrack>[
      for (final f in files)
        if (f.path case final path? when p.isWithin(root, path))
          (
            track: tracks[f.trackId] ?? Track({'id': f.trackId}),
            path: path,
            size: f.size ?? 0,
            added: f.createdAt,
          ),
    ]..sort((a, b) => a.path.compareTo(b.path));
    final playlists = <({Playlist playlist, List<String> trackIds})>[];
    for (final pin in await watchPins(PinKind.playlist).first) {
      final playlist = await cachedPlaylist?.call(pin.itemId);
      if (playlist == null) continue;
      playlists.add((
        playlist: playlist,
        trackIds: [for (final t in playlist.entries) t.id],
      ));
    }
    playlists.sort(
      (a, b) => a.playlist.name.toLowerCase().compareTo(
        b.playlist.name.toLowerCase(),
      ),
    );
    await writePlaylistFiles(
      root: root,
      tracks: inFolder,
      playlists: playlists,
      version: appVersion,
    );
  }

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
    if (orphans.isNotEmpty) _schedulePlaylists();
  }

  Future<void> _deleteFile(String trackId, String? path) async {
    await backend.cancel(trackId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      final root = _folder;
      if (root != null && p.isWithin(root, path)) {
        await pruneEmptyFolders(path, root);
      }
    }
  }

  /// The last progress written for each file, and when, to write progress at most once a second or per 5 %.
  final _written = <String, (double, DateTime)>{};

  /// Whether a progress-only update is worth a write. Every write to the track files re-runs every query that watches them, for each album, playlist and song on screen, so progress ticks are thinned out.
  bool _progressWorthWriting(String id, double progress) {
    final last = _written[id];
    final now = DateTime.now();
    if (last != null &&
        (progress - last.$1).abs() < 0.05 &&
        now.difference(last.$2) < const Duration(seconds: 1)) {
      return false;
    }
    _written[id] = (progress, now);
    return true;
  }

  Future<void> _onUpdate(TransferUpdate update) async {
    if (update.status == null &&
        update.progress != null &&
        !_progressWorthWriting(update.id, update.progress!)) {
      return;
    }
    if (update.status != null && update.status != FileStatus.downloading) {
      _written.remove(update.id);
    }
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
    if (update.status == FileStatus.complete) {
      await optimizeStorage();
      _schedulePlaylists();
    }
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
    _schedulePlaylists();
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
  )..where((t) => t.trackId.equals(trackId))).watchSingleOrNull().distinct();

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
        )
        // A write to another file re-runs the query; an unchanged state is not passed on.
        .distinct();
  }

  /// IDs of all complete track files, most recently downloaded first.
  Stream<List<String>> watchCompleteTrackIds() =>
      (db.select(db.trackFiles)
            ..where((t) => t.status.equalsValue(FileStatus.complete))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => [for (final r in rows) r.trackId])
          // Progress writes re-run the query; the same downloaded files are not passed on.
          .distinct(listEquals);

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
