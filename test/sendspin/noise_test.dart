import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/noise.dart';

/// Generated with the Python noiseprotocol library, which aiosendspin (the Sendspin library of Music Assistant) uses.
const vector = {
  'server_static':
      '42b0f52facd91e6603b9a1c026de0eb46ebcfc33fcf136a5a1c9b4980f664fb3',
  'client_static':
      'e80faf67c3eea236e1a1e2c759cdba095f94cead6b2d77e318174d4c0d2eec97',
  'server_ephemeral':
      'dab761a25f5c328a377d8eadac3fba8719d43fb0d6e7057635fcbb9b3ad466bf',
  'client_ephemeral':
      '9bf5695fcc53df3df834bc9e27dd56e778943701460e96ce96aeec090ea2d60e',
  'prologue': '7b2274797065223a22636c69656e742f696e6974227d7b2274797065223a227365727665722f696e6974227d',
  'message1': 'cd0374d498d6fcf20103ae76afc5ff7a47151fde29fe0b4819d27ab9b0d84345d21bc151807cbccb7052b06bb0e1d0dfcc842642800ff123a9e462edd6c258537228aff8c895aed467e8984b239c1d1ad0534d78bed21092e1f68b0db6a574a2b9ff2e7009b691beb35709ed4cd86a06d1b4d76d3d11f55b6fc161e9',
  'payload1': '7b2270736b5f6964223a224746735639744c6153516d3948634657704b736759514f7237774654764e55746b6d467775567a337a6f6f222c2270736b5f63617465676f7279223a22736e227d',
  'message2': '9800ec929a1e5f91081c8e11712ed8f04bff703e756efeeb5230e7ca6c6cba7100acc9053d6f2a34403ef9130c0a085fd97a',
  'ping': '686e3074935003886987bcc65589720090a57241',
  'pong': 'e360ecd80ab7f41dcf87025730a355fb8c7cf82c',
};

List<int> bytes(String key) => hex.decode(vector[key]!);

void main() {
  test(
    'the responder handshake and transport match the Python implementation',
    () async {
      final client = await StaticKey.fromPrivate(bytes('client_static'));
      final server = await StaticKey.fromPrivate(bytes('server_static'));
      final responder = await NoiseResponder.start(
        local: client,
        remoteStatic: server.publicKey,
        prologue: bytes('prologue'),
      );

      expect(
        await responder.readMessage1(bytes('message1')),
        bytes('payload1'),
      );

      final (message2, transport) = await responder.writeMessage2(
        await sentinelPsk(),
        '{}'.codeUnits,
        ephemeral: await StaticKey.fromPrivate(bytes('client_ephemeral')),
      );
      expect(message2, bytes('message2'));
      expect(
        String.fromCharCodes(await transport.receive.decrypt(bytes('ping'))),
        'ping',
      );
      expect(await transport.send.encrypt('pong'.codeUnits), bytes('pong'));
    },
  );

  test('the Sentinel PSK id is the published constant', () async {
    expect(
      await pskId(await sentinelPsk()),
      'GFsV9tLaSQm9HcFWpKsgYQOr7wFTvNUtkmFwuVz3zoo',
    );
  });

  test('a tampered message fails authentication', () async {
    final client = await StaticKey.fromPrivate(bytes('client_static'));
    final server = await StaticKey.fromPrivate(bytes('server_static'));
    final responder = await NoiseResponder.start(
      local: client,
      remoteStatic: server.publicKey,
      prologue: bytes('prologue'),
    );
    final tampered = [...bytes('message1')]..[40] ^= 1;
    expect(responder.readMessage1(tampered), throwsA(isA<NoiseException>()));
  });
}
