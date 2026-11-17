import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the app keeps credentials and keys: the keychain of the system, or a private file on a kiosk.
abstract interface class SecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

/// The keychain of the system through flutter_secure_storage.
class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore();

  // On macOS the data protection keychain needs a team entitlement, which an app built without a paid signing identity lacks; the login keychain needs none.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// A JSON file only its owner can read, for a kiosk: it has no keychain to unlock, and its provisioning file already holds the secrets in plain text.
class FileSecretStore implements SecretStore {
  FileSecretStore(this.file);

  final File file;
  Map<String, String>? _values;

  Future<Map<String, String>> _load() async {
    if (_values case final values?) return values;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _values = raw.map((k, v) => MapEntry(k, v as String));
    } on Object {
      return _values = {};
    }
  }

  Future<void> _save(Map<String, String> values) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    // Only the owner may read the file, before it holds anything.
    await temporary.writeAsString('');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', temporary.path]);
    }
    await temporary.writeAsString(jsonEncode(values), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<String?> read({required String key}) async => (await _load())[key];

  @override
  Future<void> write({required String key, required String value}) async {
    final values = await _load();
    values[key] = value;
    await _save(values);
  }

  @override
  Future<void> delete({required String key}) async {
    final values = await _load();
    if (values.remove(key) != null) await _save(values);
  }
}
