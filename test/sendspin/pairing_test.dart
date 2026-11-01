import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/listener.dart';
import 'package:puffer/sendspin/noise.dart';
import 'package:puffer/sendspin/pairing.dart';
import 'package:puffer/sendspin/session.dart';

import 'interop_test.dart' show RecordingOutput;

Uint8List bytes(int from) =>
    Uint8List.fromList([for (var i = 0; i < 32; i++) from + i]);

void main() {
  test('the pairing token matches the reference vector of the spec', () {
    final token = encodePairingToken(bytes(0x00), bytes(0xe0));
    expect(
      token,
      'SP:0AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYP6BYPC4PSOLZXH5DU6V97M5XXO74HR6LZ7J5PW674PT6X37T6757Y',
    );
    // Decoding is lenient with pasted input: case, whitespace and a missing prefix.
    final (key, psk) = decodePairingToken(
      '  ${token.substring(3).toLowerCase()}\n',
    );
    expect(key, bytes(0x00));
    expect(psk, bytes(0xe0));
    expect(() => decodePairingToken('SP:1AAAA'), throwsFormatException);
    expect(() => decodePairingToken('SP:0AAAA'), throwsFormatException);
  });

  test('records replace the earlier one of a server and evict the least recently used spare one', () {
    final saved = <List<PairingRecord>>[];
    final store = PairingStore(pairingPsk: randomKey(), onChanged: saved.add)
      ..inUse = () => {'s0'};
    for (var i = 0; i < PairingStore.capacity; i++) {
      store.save('s$i', randomKey());
    }
    final replacement = randomKey();
    store.save('s3', replacement);
    expect(store.records, hasLength(PairingStore.capacity));
    expect(store.recordFor('s3')!.longTermPsk, replacement);

    // At capacity, s0 backs an open connection, so s1 goes.
    store.save('new', randomKey());
    expect(store.records, hasLength(PairingStore.capacity));
    expect(store.recordFor('s0'), isNotNull);
    expect(store.recordFor('s1'), isNull);

    final restored = PairingStore.decodeRecords(
      PairingStore.encodeRecords(saved.last),
    );
    expect(
      restored.map((r) => r.serverId),
      store.records.map((r) => r.serverId),
    );
    expect(restored.last.longTermPsk, store.records.last.longTermPsk);
  });

  final python = Platform.environment['SENDSPIN_PYTHON'];

  test(
    'aiosendspin pairs with the token, plays on the paired session and finds the pairing again',
    () async {
      final identity = await StaticKey.generate();
      final store = PairingStore(pairingPsk: randomKey());
      final output = RecordingOutput();
      final listener = SendspinListener(
        config: SendspinConfig(
          identity: identity,
          name: 'Puffer pairing test',
          pairing: store,
        ),
        output: output,
        port: 0,
      );
      await listener.start();
      final process = await Process.start(python!, [
        'test/sendspin/interop_pairing.py',
        'ws://127.0.0.1:${listener.boundPort}/sendspin',
        encodePairingToken(identity.publicKey, store.pairingPsk),
      ]);
      final lines = <String>[];
      final done = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            lines.add(line);
            if (line == 'DONE' || line.startsWith('TIMEOUT')) {
              if (!done.isCompleted) done.complete();
            }
          });
      process.stderr.transform(utf8.decoder).listen(stderr.write);
      await Future.any([done.future, process.exitCode])
          .timeout(const Duration(seconds: 90));
      await listener.stop();
      process.kill();

      expect(lines, containsAllInOrder(['PAIRED', 'STREAMED', 'RECONNECTED']));
      expect(store.records, hasLength(1));
      expect(output.chunks, isNotEmpty);
    },
    skip: python == null
        ? 'set SENDSPIN_PYTHON to run against aiosendspin'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
