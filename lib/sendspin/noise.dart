// The Noise handshake of Sendspin: Noise_KKpsk2_25519_ChaChaPoly_SHA256, with the server as initiator and this client as responder (noiseprotocol.org/noise.html).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final _x25519 = X25519();
final _aead = Chacha20.poly1305Aead();
final _sha256 = Sha256();
final _hmac = Hmac.sha256();

const suiteName = '25519_ChaChaPoly_SHA256';
const _protocolName = 'Noise_KKpsk2_$suiteName';

class NoiseException implements Exception {
  const NoiseException(this.message);

  final String message;

  @override
  String toString() => 'NoiseException: $message';
}

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

Future<Uint8List> sha256(List<int> data) async =>
    Uint8List.fromList((await _sha256.hash(data)).bytes);

Future<Uint8List> _hmacSha256(List<int> key, List<int> data) async =>
    Uint8List.fromList(
      (await _hmac.calculateMac(data, secretKey: SecretKey(key))).bytes,
    );

/// HKDF of the Noise specification, returning [outputs] (2 or 3) keys of 32 bytes.
Future<List<Uint8List>> _hkdf(
  List<int> chainingKey,
  List<int> inputKeyMaterial,
  int outputs,
) async {
  final tempKey = await _hmacSha256(chainingKey, inputKeyMaterial);
  final out1 = await _hmacSha256(tempKey, [1]);
  final out2 = await _hmacSha256(tempKey, [...out1, 2]);
  if (outputs == 2) return [out1, out2];
  final out3 = await _hmacSha256(tempKey, [...out2, 3]);
  return [out1, out2, out3];
}

/// ChaChaPoly nonce: 32 bits of zeros followed by the 64-bit counter, little-endian.
Uint8List _nonce(int n) {
  final nonce = Uint8List(12);
  ByteData.sublistView(nonce).setUint64(4, n, Endian.little);
  return nonce;
}

/// A key with its nonce counter: one direction of the transport, or the handshake's symmetric state.
class CipherState {
  CipherState([this._key]);

  Uint8List? _key;
  int _n = 0;

  bool get hasKey => _key != null;

  Future<Uint8List> encrypt(
    List<int> plaintext, {
    List<int> ad = const [],
  }) async {
    final key = _key;
    if (key == null) return Uint8List.fromList(plaintext);
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: _nonce(_n++),
      aad: ad,
    );
    return _concat([box.cipherText, box.mac.bytes]);
  }

  Future<Uint8List> decrypt(
    List<int> ciphertext, {
    List<int> ad = const [],
  }) async {
    final key = _key;
    if (key == null) return Uint8List.fromList(ciphertext);
    if (ciphertext.length < 16)
      throw const NoiseException('ciphertext shorter than its tag');
    final box = SecretBox(
      ciphertext.sublist(0, ciphertext.length - 16),
      nonce: _nonce(_n),
      mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
    );
    try {
      final plain = await _aead.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: ad,
      );
      _n++;
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const NoiseException('authentication failed');
    }
  }
}

/// A Curve25519 key pair; its public key encoded as base64url without padding is the Sendspin client or server id.
class StaticKey {
  StaticKey._(this.privateKey, this.publicKey, this._pair);

  final Uint8List privateKey;
  final Uint8List publicKey;
  final SimpleKeyPair _pair;

  static Future<StaticKey> fromPrivate(List<int> privateKey) async {
    final pair = await _x25519.newKeyPairFromSeed(privateKey);
    final public = await pair.extractPublicKey();
    return StaticKey._(
      Uint8List.fromList(privateKey),
      Uint8List.fromList(public.bytes),
      pair,
    );
  }

  static Future<StaticKey> generate() async {
    final pair = await _x25519.newKeyPair();
    return fromPrivate(await pair.extractPrivateKeyBytes());
  }

  String get id => base64UrlNoPad(publicKey);

  Future<Uint8List> dh(List<int> remotePublic) async {
    final secret = await _x25519.sharedSecretKey(
      keyPair: _pair,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await secret.extractBytes());
  }
}

String base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List base64UrlDecodeNoPad(String text) =>
    base64Url.decode(text.padRight((text.length + 3) ~/ 4 * 4, '='));

/// The responder side of the KKpsk2 handshake:
///
///     -> s
///     <- s
///     ...
///     -> e, es, ss
///     <- e, ee, se, psk
class NoiseResponder {
  NoiseResponder._(this._local, this._remoteStatic, this._h, this._ck);

  final StaticKey _local;
  final Uint8List _remoteStatic;
  Uint8List _h;
  Uint8List _ck;
  final _cipher = CipherState();
  Uint8List? _remoteEphemeral;

  /// Starts the handshake with the server's static key [remoteStatic] and the [prologue] (client/init followed by server/init, as sent).
  static Future<NoiseResponder> start({
    required StaticKey local,
    required List<int> remoteStatic,
    required List<int> prologue,
  }) async {
    // The protocol name is longer than 32 bytes, so h starts as its hash.
    final h = await sha256(utf8.encode(_protocolName));
    final responder = NoiseResponder._(
      local,
      Uint8List.fromList(remoteStatic),
      h,
      Uint8List.fromList(h),
    );
    await responder._mixHash(prologue);
    // Pre-messages: the initiator's static key, then the responder's.
    await responder._mixHash(remoteStatic);
    await responder._mixHash(local.publicKey);
    return responder;
  }

  Future<void> _mixHash(List<int> data) async =>
      _h = await sha256(_concat([_h, data]));

  Future<void> _mixKey(List<int> inputKeyMaterial) async {
    final out = await _hkdf(_ck, inputKeyMaterial, 2);
    _ck = out[0];
    _cipher._key = out[1];
    _cipher._n = 0;
  }

  Future<void> _mixKeyAndHash(List<int> inputKeyMaterial) async {
    final out = await _hkdf(_ck, inputKeyMaterial, 3);
    _ck = out[0];
    await _mixHash(out[1]);
    _cipher._key = out[2];
    _cipher._n = 0;
  }

  Future<Uint8List> _encryptAndHash(List<int> plaintext) async {
    final c = await _cipher.encrypt(plaintext, ad: _h);
    await _mixHash(c);
    return c;
  }

  Future<Uint8List> _decryptAndHash(List<int> ciphertext) async {
    final p = await _cipher.decrypt(ciphertext, ad: _h);
    await _mixHash(ciphertext);
    return p;
  }

  /// Reads message 1 (`e, es, ss`) and returns its payload, which is readable before the PSK is known.
  Future<Uint8List> readMessage1(List<int> message) async {
    if (message.length < 32 + 16)
      throw const NoiseException('message 1 too short');
    final re = Uint8List.fromList(message.sublist(0, 32));
    _remoteEphemeral = re;
    await _mixHash(re);
    // With a PSK in the pattern, every "e" token also mixes the key.
    await _mixKey(re);
    await _mixKey(await _local.dh(re)); // es
    await _mixKey(await _local.dh(_remoteStatic)); // ss
    return _decryptAndHash(message.sublist(32));
  }

  /// Writes message 2 (`e, ee, se, psk`) with [payload] and returns it with the two transport ciphers.
  Future<(Uint8List, NoiseTransport)> writeMessage2(
    List<int> psk,
    List<int> payload, {
    StaticKey? ephemeral,
  }) async {
    final re = _remoteEphemeral;
    if (re == null) throw const NoiseException('message 1 not read');
    final e = ephemeral ?? await StaticKey.generate();
    await _mixHash(e.publicKey);
    await _mixKey(e.publicKey);
    await _mixKey(await e.dh(re)); // ee
    await _mixKey(await e.dh(_remoteStatic)); // se
    await _mixKeyAndHash(psk);
    final body = await _encryptAndHash(payload);
    final keys = await _hkdf(_ck, const [], 2);
    // The initiator sends with the first key, so the responder receives with it.
    return (
      _concat([e.publicKey, body]),
      NoiseTransport(
        send: CipherState(keys[1]),
        receive: CipherState(keys[0]),
        handshakeHash: _h,
      ),
    );
  }
}

class NoiseTransport {
  NoiseTransport({
    required this.send,
    required this.receive,
    required this.handshakeHash,
  });

  final CipherState send;
  final CipherState receive;
  final Uint8List handshakeHash;
}

/// The Sentinel PSK, a published constant used when no other PSK applies.
Future<Uint8List> sentinelPsk() =>
    sha256(utf8.encode('sendspin-sentinel-psk-v1'));

/// The identifier a server sends in message 1 to name the PSK it uses.
Future<String> pskId(List<int> psk) async => base64UrlNoPad(
  await sha256([...utf8.encode('sendspin-psk-id-v1'), ...psk]),
);
