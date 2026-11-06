import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/artwork_cache.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';

void main() {
  const credentials = ServerCredentials(
    baseUrl: 'http://navidrome',
    username: 'u',
    token: 'secret-token',
    salt: 'secret-salt',
  );

  test('the URL the artwork cache stores holds no credentials', () {
    final uri = SubsonicClient(credentials)
        .unsignedCoverArtUri('al-1', size: 600);
    expect(uri.queryParameters, isNot(contains('t')));
    expect(uri.queryParameters, isNot(contains('s')));
    expect(uri.queryParameters, isNot(contains('apiKey')));
    expect(uri.queryParameters['id'], 'al-1');
    expect(uri.queryParameters['size'], '600');
  });

  test(
    'the artwork cache adds the credentials when it sends a request',
    () async {
      late Uri sent;
      final service = SigningFileService(
        () => credentials.authParams,
        httpClient: MockClient((request) async {
          sent = request.url;
          return http.Response('', 200);
        }),
      );
      final unsigned = SubsonicClient(credentials)
          .unsignedCoverArtUri('al-1', size: 600);
      await service.get(unsigned.toString());
      expect(sent.queryParameters['t'], 'secret-token');
      expect(sent.queryParameters['s'], 'secret-salt');
      expect(sent.queryParameters['id'], 'al-1');
      expect(sent.queryParameters['size'], '600');
    },
  );

  test('without a session the URL goes out unchanged', () {
    expect(
      signUrl('http://x/rest/getCoverArt?id=1', null),
      'http://x/rest/getCoverArt?id=1',
    );
  });
}
