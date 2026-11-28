import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';

class _FakeClient extends Mock implements MusicAssistantClient {}

class _Output extends OutputNotifier {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

class _Visible extends AppVisibleNotifier {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

void main() {
  late _FakeClient client;
  late ProviderContainer container;

  setUp(() {
    client = _FakeClient();
    container = ProviderContainer(
      overrides: [
        maClientProvider.overrideWithValue(client),
        outputProvider.overrideWith(_Output.new),
        appVisibleProvider.overrideWith(_Visible.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(maEagerReconnectProvider, (_, _) {});
  });

  _Output output() => container.read(outputProvider.notifier) as _Output;
  _Visible visible() => container.read(appVisibleProvider.notifier) as _Visible;

  test('playing on this device, retries back off', () {
    verifyNever(() => client.startWaiting());
  });

  test('on a speaker, a lost connection is retried at once', () async {
    output().set('kitchen');
    await container.pump();
    verify(() => client.startWaiting()).called(1);

    output().set(null);
    await container.pump();
    verify(() => client.stopWaiting()).called(1);
  });

  test('hidden, retries back off even on a speaker', () async {
    output().set('kitchen');
    await container.pump();
    verify(() => client.startWaiting()).called(1);

    visible().set(false);
    await container.pump();
    verify(() => client.stopWaiting()).called(1);
    verifyNever(() => client.startWaiting());

    visible().set(true);
    await container.pump();
    verify(() => client.startWaiting()).called(1);
  });
}
