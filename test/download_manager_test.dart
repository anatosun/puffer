import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/downloads/download_manager.dart';
import 'package:puffer/downloads/download_settings.dart';
import 'package:puffer/downloads/transfer_backend.dart';

class FakeBackend implements TransferBackend {
  final controller = StreamController<TransferUpdate>.broadcast();
  final enqueued = <String>[];
  final cancelled = <String>[];

  @override
  Stream<TransferUpdate> get updates => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> enqueue({
    required String id,
    required Uri url,
    required String directory,
    required String filename,
    required bool wifiOnly,
  }) async => enqueued.add(id);

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}

Track track(String id) => Track({'id': id, 'title': id, 'suffix': 'flac'});

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late DownloadManager manager;
  late Directory dir;
  late Map<(PinKind, String), List<Track>> library;
  var settings = const DownloadSettings();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    dir = await Directory.systemTemp.createTemp('downloads_test');
    settings = const DownloadSettings();
    library = {
      (PinKind.album, 'album1'): [track('t1'), track('t2')],
      (PinKind.playlist, 'pl1'): [track('t2'), track('t3')],
      (PinKind.track, 't1'): [track('t1')],
    };
    manager = DownloadManager(
      db: db,
      backend: backend,
      resolve: (kind, id) async => library[(kind, id)]!,
      urlFor: (t, q) => Uri.parse('http://server/${t.id}'),
      settings: () => settings,
    );
    await manager.start();
  });

  tearDown(() async {
    await manager.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> complete(String id, {int bytes = 100}) async {
    final file = File('${dir.path}/$id')
      ..writeAsBytesSync(List.filled(bytes, 0));
    backend.controller.add(
      TransferUpdate(id, status: FileStatus.complete, path: file.path),
    );
    await pumpEventQueue();
  }

  Future<Set<String>> fileIds() async => {
    for (final f in await db.select(db.trackFiles).get()) f.trackId,
  };

  test('pinning an album downloads its tracks', () async {
    await manager.pin(PinKind.album, 'album1');
    expect(backend.enqueued, ['t1', 't2']);
    expect(await fileIds(), {'t1', 't2'});
  });

  test('removing an album keeps tracks a downloaded playlist holds', () async {
    await manager.pin(PinKind.album, 'album1');
    await manager.pin(PinKind.playlist, 'pl1');
    expect(backend.enqueued, ['t1', 't2', 't3']);

    await manager.unpin(PinKind.album, 'album1');
    expect(await fileIds(), {'t2', 't3'});
    expect(backend.cancelled, ['t1']);
  });

  test('a downloaded playlist follows changes on sync', () async {
    await manager.pin(PinKind.playlist, 'pl1');
    library[(PinKind.playlist, 'pl1')] = [track('t3'), track('t4')];

    await manager.syncPins();
    expect(await fileIds(), {'t3', 't4'});
  });

  test('automatic downloads do not take over a pin the person made', () async {
    await manager.pin(PinKind.track, 't1');
    await manager.syncAutomatic(
      Starred(artists: const [], albums: const [], tracks: [track('t1')]),
    );
    final pin = await db.select(db.pins).getSingle();
    expect(pin.automatic, isFalse);

    await manager.syncAutomatic(
      const Starred(artists: [], albums: [], tracks: []),
    );
    expect(await fileIds(), {'t1'});
  });

  test('unstarring an item releases its automatic pin', () async {
    await manager.syncAutomatic(
      Starred(artists: const [], albums: const [], tracks: [track('t1')]),
    );
    expect(await fileIds(), {'t1'});

    await manager.syncAutomatic(
      const Starred(artists: [], albums: [], tracks: []),
    );
    expect(await fileIds(), isEmpty);
  });

  test('pin state aggregates track progress', () async {
    await manager.pin(PinKind.album, 'album1');
    expect(
      await manager.watchPin(PinKind.album, 'album1').first,
      isA<PinState>().having((s) => s.isDownloading, 'downloading', isTrue),
    );

    await complete('t1');
    await complete('t2');
    final state = await manager.watchPin(PinKind.album, 'album1').first;
    expect(state.isComplete, isTrue);
    expect(state.total, 2);
  });

  test('a download whose tracks cannot be listed pins nothing', () async {
    await expectLater(
      manager.pin(PinKind.album, 'unknown'),
      throwsA(isA<TypeError>()),
    );
    expect(
      await manager.watchPin(PinKind.album, 'unknown').first,
      PinState.none,
    );
  });

  test('a pin that fails to sync does not stop the others', () async {
    await manager.pin(PinKind.album, 'album1');
    await manager.pin(PinKind.playlist, 'pl1');
    library.remove((PinKind.album, 'album1'));
    library[(PinKind.playlist, 'pl1')] = [track('t3'), track('t4')];

    await manager.syncPins();
    expect(backend.enqueued, contains('t4'));
    expect(await fileIds(), containsAll(['t1', 't2']));
  });

  test('a pinned playlist without tracks is complete', () async {
    library[(PinKind.playlist, 'empty')] = [];
    await manager.pin(PinKind.playlist, 'empty');
    final state = await manager.watchPin(PinKind.playlist, 'empty').first;
    expect(state.isComplete, isTrue);
    expect(state.isDownloading, isFalse);
  });

  test('a pin shows as downloading while its tracks are listed', () async {
    final listed = Completer<List<Track>>();
    await manager.dispose();
    manager = DownloadManager(
      db: db,
      backend: backend,
      resolve: (kind, id) => listed.future,
      urlFor: (t, q) => Uri.parse('http://server/${t.id}'),
      settings: () => settings,
    );
    final states = <PinState>[];
    final subscription = manager
        .watchPin(PinKind.playlist, 'slow')
        .listen(states.add);
    final pinning = manager.pin(PinKind.playlist, 'slow');
    await pumpEventQueue();
    expect(states.last.isDownloading, isTrue);

    listed.complete([]);
    await pinning;
    await pumpEventQueue();
    expect(states.last.isComplete, isTrue);
    await subscription.cancel();
  });

  test('optimize storage evicts only files held by automatic pins', () async {
    settings = const DownloadSettings(
      optimizeStorage: true,
      storageLimitBytes: 150,
    );
    await manager.pin(PinKind.album, 'album1');
    library[(PinKind.track, 't3')] = [track('t3')];
    await manager.syncAutomatic(
      Starred(artists: const [], albums: const [], tracks: [track('t3')]),
    );

    await complete('t1');
    await complete('t2');
    await complete('t3');

    final files = {
      for (final f in await db.select(db.trackFiles).get()) f.trackId: f.status,
    };
    expect(files, {
      't1': FileStatus.complete,
      't2': FileStatus.complete,
      't3': FileStatus.evicted,
    });
  });

  test(
    'transfers list downloading files first and leave out complete ones',
    () async {
      await manager.pin(PinKind.album, 'album1');
      await manager.pin(PinKind.playlist, 'pl1');
      await complete('t1');
      backend.controller.add(
        const TransferUpdate(
          't3',
          status: FileStatus.downloading,
          progress: 0.5,
        ),
      );
      await pumpEventQueue();
      final transfers = await manager.watchTransfers().first;
      expect(transfers.map((f) => f.trackId), ['t3', 't2']);
      expect(transfers.first.progress, 0.5);
    },
  );

  test('remove all deletes every pin and file', () async {
    await manager.pin(PinKind.album, 'album1');
    await complete('t1');
    await manager.removeAll();
    expect(await fileIds(), isEmpty);
    expect(await db.select(db.pins).get(), isEmpty);
    expect(File('${dir.path}/t1').existsSync(), isFalse);
  });
}
