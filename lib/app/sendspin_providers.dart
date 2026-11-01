import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sendspin/noise.dart';
import '../sendspin/pairing.dart';
import '../sendspin/sendspin_service.dart';
import '../sendspin/session.dart';
import '../ui/messages.dart';
import 'providers.dart';

/// Whether the phone is a Sendspin speaker that Music Assistant can play on.
final sendspinEnabledProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('sendspin.enabled', false),
);

class SendspinNameNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.read(sharedPreferencesProvider).getString('sendspin.name') ??
      'Puffer';

  Future<void> set(String name) async {
    // The specification caps names at 64 bytes of UTF-8.
    final trimmed = name.trim().characters.take(40).toString();
    if (trimmed.isEmpty) return;
    state = trimmed;
    await ref
        .read(sharedPreferencesProvider)
        .setString('sendspin.name', trimmed);
  }
}

/// The name Music Assistant shows for this speaker.
final sendspinNameProvider = NotifierProvider<SendspinNameNotifier, String>(
  SendspinNameNotifier.new,
);

const _identityKey = 'sendspin.identity';
const _pairingPskKey = 'sendspin.pairingPsk';
const _pairingsKey = 'sendspin.pairings';

/// The pairing PSK, made once per installation and kept across restarts, and the pairing records, saved after each change. Both live in secure storage.
Future<PairingStore> _loadPairing() async {
  final stored = await secureStorage.read(key: _pairingPskKey);
  final psk = stored == null ? randomKey() : base64UrlDecodeNoPad(stored);
  if (stored == null) {
    await secureStorage.write(key: _pairingPskKey, value: base64UrlNoPad(psk));
  }
  return PairingStore(
    pairingPsk: psk,
    records: PairingStore.decodeRecords(
      await secureStorage.read(key: _pairingsKey),
    ),
    onChanged: (records) => unawaited(
      secureStorage.write(
        key: _pairingsKey,
        value: PairingStore.encodeRecords(records),
      ),
    ),
  );
}

/// Runs the speaker while it is switched on. Its identity, a key pair, persists so Music Assistant recognises the phone across restarts.
final sendspinServiceProvider = FutureProvider<SendspinService?>((ref) async {
  if (!ref.watch(sendspinEnabledProvider)) return null;
  final name = ref.watch(sendspinNameProvider);
  final stored = await secureStorage.read(key: _identityKey);
  final identity = await SendspinService.identityFrom(stored);
  if (stored == null) {
    await secureStorage.write(
      key: _identityKey,
      value: SendspinService.encodeIdentity(identity),
    );
  }
  final service = SendspinService(
    name: name,
    identity: identity,
    pairing: await _loadPairing(),
    // Music Assistant taking over the speaker pauses what plays on the phone itself.
    onPlaybackStarted: () => ref.read(playerHandlerProvider).pause(),
  );
  try {
    await service.start();
  } on Exception catch (e) {
    showMessage('The speaker could not start: $e');
    return null;
  }
  ref.onDispose(service.stop);
  return service;
});

/// The Music Assistant player of this phone as a speaker. Music Assistant names Sendspin players by their client id, the public key of the speaker.
final ownSpeakerIdProvider = Provider<String?>(
  (ref) => ref.watch(sendspinServiceProvider).value?.identity.id,
);

final sendspinStatusProvider = StreamProvider<SendspinStatus>((ref) async* {
  final service = await ref.watch(sendspinServiceProvider.future);
  if (service == null) {
    yield const SendspinStatus();
    return;
  }
  yield service.status;
  yield* service.statusStream;
});
