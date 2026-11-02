import 'package:http/http.dart' as http;

import 'subsonic_client.dart';

/// How long the local address has to answer before the public address is used.
const localProbeTimeout = Duration(seconds: 3);

/// The address to reach the server through: the local address when the device is on Wi-Fi or Ethernet and the server answers there, otherwise the public address.
Future<String> chooseAddress(
  ServerCredentials credentials, {
  required bool onLocalNetwork,
  required Future<bool> Function(String url) answers,
}) async {
  final local = credentials.localUrl;
  if (local != null && onLocalNetwork && await answers(local)) return local;
  return credentials.baseUrl;
}

/// Whether the server answers a `ping` with [credentials] at [url] within [timeout].
Future<bool> serverAnswers(
  ServerCredentials credentials,
  String url, {
  Duration timeout = localProbeTimeout,
  http.Client? httpClient,
}) async {
  final client = SubsonicClient(
    credentials,
    baseUrl: url,
    httpClient: httpClient,
  );
  try {
    await client.ping(timeout: timeout);
    return true;
  } on Exception {
    return false;
  } finally {
    client.close();
  }
}
