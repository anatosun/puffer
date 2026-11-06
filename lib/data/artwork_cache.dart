import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The disk cache of the cover images the server sends. Its database holds URLs without credentials: [authParams] are added to each request when it is sent, so neither the cache nor the logs of the cache hold a token, salt or API key.
CacheManager artworkCacheManager(Map<String, String>? Function() authParams) =>
    CacheManager(
      Config(
        artworkCacheKey,
        stalePeriod: const Duration(days: 60),
        maxNrOfCacheObjects: 4000,
        fileService: SigningFileService(authParams),
      ),
    );

const artworkCacheKey = 'puffer-artwork';

/// Fetches a URL after adding [authParams] to its query.
class SigningFileService extends HttpFileService {
  SigningFileService(this.authParams, {super.httpClient});

  final Map<String, String>? Function() authParams;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) =>
      super.get(signUrl(url, authParams()), headers: headers);
}

/// [url] with [auth] added to its query; unchanged when [auth] is null.
String signUrl(String url, Map<String, String>? auth) {
  if (auth == null) return url;
  final uri = Uri.parse(url);
  return uri
      .replace(queryParameters: {...uri.queryParameters, ...auth})
      .toString();
}
