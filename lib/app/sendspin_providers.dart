import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final sendspinStatusProvider = StreamProvider<SendspinStatus>((ref) async* {
  final service = await ref.watch(sendspinServiceProvider.future);
  if (service == null) {
    yield const SendspinStatus();
    return;
  }
  yield service.status;
  yield* service.statusStream;
});
