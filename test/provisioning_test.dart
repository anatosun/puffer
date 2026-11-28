import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/provisioning.dart';
import 'package:puffer/core/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('puffer-provisioning'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes the credentials and settings of the file', () async {
    SharedPreferences.setMockInitialValues({'sendspin.enabled': false});
    final prefs = await SharedPreferences.getInstance();
    final secrets = FileSecretStore(File('${dir.path}/secrets.json'));
    await Provisioning.parse(
      jsonEncode({
        'subsonic': {
          'url': 'music.example.org',
          'username': 'kiosk',
          'password': 'secret',
          'localUrl': '192.168.1.10:4533',
        },
        'musicAssistant': {'url': 'http://192.168.1.20:8095', 'token': ' abc '},
        'settings': {
          'sendspin.enabled': true,
          'sendspin.name': 'Kitchen',
          'ma.stayOnSpeaker': true,
        },
      }),
    ).apply(secrets, prefs);

    final server = jsonDecode(
      (await secrets.read(key: credentialsKey))!,
    ) as Map<String, dynamic>;
    expect(server['username'], 'kiosk');
    expect(server['token'], isNotNull);
    expect(server['salt'], isNotNull);
    expect(server, isNot(contains('password')));
    expect(server['localUrl'], isNotNull);
    final ma = MaCredentials.fromJson(
      jsonDecode((await secrets.read(key: maCredentialsKey))!)
          as Map<String, dynamic>,
    );
    expect(ma.token, 'abc');
    expect(ma.baseUrl.port, 8095);
    expect(prefs.getBool('sendspin.enabled'), isTrue);
    expect(prefs.getString('sendspin.name'), 'Kitchen');
    expect(prefs.getBool('ma.stayOnSpeaker'), isTrue);
  });

  test('a section left out keeps what the app has', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = FileSecretStore(File('${dir.path}/secrets.json'));
    await secrets.write(key: maCredentialsKey, value: 'kept');
    await Provisioning.parse(
      jsonEncode({
        'subsonic': {'url': 'https://music.example.org', 'apiKey': 'key'},
      }),
    ).apply(secrets, prefs);
    expect(await secrets.read(key: maCredentialsKey), 'kept');
    final server = jsonDecode(
      (await secrets.read(key: credentialsKey))!,
    ) as Map<String, dynamic>;
    expect(server['apiKey'], 'key');
  });

  test(
    'the secret file survives a restart and only its owner reads it',
    () async {
      final file = File('${dir.path}/secrets.json');
      await FileSecretStore(file).write(key: 'a', value: '1');
      expect(await FileSecretStore(file).read(key: 'a'), '1');
      if (!Platform.isWindows) {
        expect(file.statSync().modeString(), 'rw-------');
      }
      await FileSecretStore(file).delete(key: 'a');
      expect(await FileSecretStore(file).read(key: 'a'), isNull);
    },
  );

  test('a Music Assistant URL without http is skipped, not added to', () {
    final provisioning = Provisioning.parse(
      jsonEncode({
        'musicAssistant': {'url': '192.168.1.20', 'token': 'abc'},
      }),
    );
    expect(provisioning.musicAssistant, isNull);
  });
}
