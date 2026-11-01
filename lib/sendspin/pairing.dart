// Pairing of the Sendspin speaker with servers: the pairing PSK and its token, and the pairing records that pairing produces (spec: "Pairing").

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'noise.dart';

const _base32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// 32 bytes from a CSPRNG.
Uint8List randomKey() {
  final random = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < 32; i++) random.nextInt(256)]);
}

/// RFC 4648 base32 without padding.
String _base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_base32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List _base32Decode(String text) {
  final out = BytesBuilder();
  var buffer = 0, bits = 0;
  for (final char in text.split('')) {
    final value = _base32.indexOf(char);
    if (value < 0) throw const FormatException('not base32');
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      out.addByte((buffer >> (bits - 8)) & 0xFF);
      bits -= 8;
      buffer &= (1 << bits) - 1;
    }
  }
  return out.toBytes();
}

/// The version-0 pairing token the operator pastes into the server: `SP:0` and the base32 of the client key followed by the pairing PSK, with every `2` written as `9` so the token stays in the QR alphanumeric set.
String encodePairingToken(List<int> clientKey, List<int> pairingPsk) =>
    'SP:0${_base32Encode([...clientKey, ...pairingPsk]).replaceAll('2', '9')}';

/// Decodes a version-0 token into the client key and the pairing PSK, leniently as the spec asks of operator input.
(Uint8List, Uint8List) decodePairingToken(String token) {
  var text = token.trim().toUpperCase();
  if (text.startsWith('SP:')) text = text.substring(3);
  if (text.isEmpty || text[0] != '0') {
    throw const FormatException('unsupported pairing token version');
  }
  final payload = _base32Decode(text.substring(1).replaceAll('9', '2'));
  if (payload.length < 64) {
    throw const FormatException('pairing token too short');
  }
  return (
    Uint8List.sublistView(payload, 0, 32),
    Uint8List.sublistView(payload, 32, 64),
  );
}

/// The long-term PSK shared with one server, kept with the server's id.
class PairingRecord {
  PairingRecord(this.serverId, this.longTermPsk, this.lastUsed);

  factory PairingRecord.fromJson(Map<String, dynamic> json) => PairingRecord(
    json['server_id'] as String,
    base64UrlDecodeNoPad(json['psk'] as String),
    DateTime.fromMillisecondsSinceEpoch(json['last_used'] as int),
  );

  final String serverId;
  final Uint8List longTermPsk;
  DateTime lastUsed;

  Map<String, dynamic> toJson() => {
    'server_id': serverId,
    'psk': base64UrlNoPad(longTermPsk),
    'last_used': lastUsed.millisecondsSinceEpoch,
  };
}

/// The pairing PSK of this speaker and its pairing records. [onChanged] persists the records after each change.
class PairingStore {
  PairingStore({
    required this.pairingPsk,
    List<PairingRecord> records = const [],
    this.onChanged,
  }) : _records = [...records];

  /// The spec asks for room for at least five records.
  static const capacity = 8;

  final Uint8List pairingPsk;
  final List<PairingRecord> _records;
  final void Function(List<PairingRecord> records)? onChanged;

  /// Servers whose records back an open connection, which eviction spares.
  Set<String> Function() inUse = () => const {};

  List<PairingRecord> get records => List.unmodifiable(_records);

  PairingRecord? recordFor(String serverId) {
    for (final r in _records) {
      if (r.serverId == serverId) return r;
    }
    return null;
  }

  /// Keeps [psk] as the long-term PSK of [serverId], replacing its earlier record. At capacity, the least recently used record of a server without an open connection makes room.
  void save(String serverId, Uint8List psk) {
    _records.removeWhere((r) => r.serverId == serverId);
    if (_records.length >= capacity) {
      final busy = inUse();
      final evictable = _records.where((r) => !busy.contains(r.serverId));
      if (evictable.isNotEmpty) {
        _records.remove(
          evictable.reduce((a, b) => a.lastUsed.isBefore(b.lastUsed) ? a : b),
        );
      }
    }
    _records.add(PairingRecord(serverId, psk, DateTime.now()));
    onChanged?.call(records);
  }

  void remove(String serverId) {
    _records.removeWhere((r) => r.serverId == serverId);
    onChanged?.call(records);
  }

  void touch(String serverId) {
    recordFor(serverId)?.lastUsed = DateTime.now();
    onChanged?.call(records);
  }

  static String encodeRecords(List<PairingRecord> records) =>
      jsonEncode([for (final r in records) r.toJson()]);

  static List<PairingRecord> decodeRecords(String? stored) => stored == null
      ? const []
      : [
          for (final r in jsonDecode(stored) as List)
            PairingRecord.fromJson(r as Map<String, dynamic>),
        ];
}
