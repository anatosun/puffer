import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../../ui/widgets/item_actions.dart';
import '../home/home_page.dart';
import '../library/album_lists.dart';
import '../library/library_page.dart';

/// What the server reports about itself. Invalidating it tests the connection again.
final serverInfoProvider = FutureProvider.autoDispose<ServerInfo?>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null || ref.watch(isOfflineProvider)) return null;
  return client.serverInfo();
});

/// Whether the signed-in user administers the server. False when the server cannot tell.
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null || ref.watch(isOfflineProvider)) return false;
  try {
    return await client.isAdmin();
  } on Exception {
    return false;
  }
});

/// Reloads the lists that show library content, after a scan or a cache refresh.
void reloadLibraryViews(Ref ref) {
  ref
    ..invalidate(albumListProvider)
    ..invalidate(playlistsProvider)
    ..invalidate(artistsProvider)
    ..invalidate(genresProvider)
    ..invalidate(pagedAlbumsProvider)
    ..invalidate(starredProvider)
    ..invalidate(downloadedTracksProvider);
}

/// The library scan of the server. While a scan runs, the status is polled every two seconds; when it ends, the library views reload.
class ScanNotifier extends AsyncNotifier<ScanStatus?> {
  static const pollInterval = Duration(seconds: 2);
  Timer? _poll;

  @override
  Future<ScanStatus?> build() async {
    ref.onDispose(() => _poll?.cancel());
    final client = ref.watch(clientProvider);
    if (client == null || ref.watch(isOfflineProvider)) return null;
    final status = await client.getScanStatus();
    if (status.scanning) _follow(client);
    return status;
  }

  Future<void> start() async {
    final client = ref.read(clientProvider);
    if (client == null) return;
    state = await AsyncValue.guard(client.startScan);
    if (state.value?.scanning ?? false) _follow(client);
  }

  void _follow(SubsonicClient client) {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (timer) async {
      try {
        final status = await client.getScanStatus();
        if (!ref.mounted) return;
        state = AsyncData(status);
        if (!status.scanning) {
          timer.cancel();
          reloadLibraryViews(ref);
        }
      } on Exception {
        // Keep the last status and try again at the next tick.
      }
    });
  }
}

final scanProvider =
    AsyncNotifierProvider.autoDispose<ScanNotifier, ScanStatus?>(
      ScanNotifier.new,
    );

/// Progress of a library cache refresh: the reloaded items and their total. Null when no refresh runs.
typedef CacheRefreshProgress = ({int done, int total});

class CacheRefreshNotifier extends Notifier<CacheRefreshProgress?> {
  @override
  CacheRefreshProgress? build() => null;

  Future<void> run() async {
    final repository = ref.read(repositoryProvider);
    if (repository == null || state != null) return;
    state = (done: 0, total: 0);
    try {
      await repository.refreshCache(
        onProgress: (done, total) => state = (done: done, total: total),
      );
    } finally {
      state = null;
      reloadLibraryViews(ref);
    }
  }
}

final cacheRefreshProvider =
    NotifierProvider<CacheRefreshNotifier, CacheRefreshProgress?>(
      CacheRefreshNotifier.new,
    );

/// The connection details as edited on the Connection page, before they are checked and saved. An empty password or API key keeps the current one; it is required when the username or the kind of authentication changes. Throws a [FormatException] with a message for the person otherwise.
ServerCredentials editedCredentials(
  ServerCredentials current, {
  required String address,
  required String localAddress,
  required String username,
  required String password,
  required String apiKey,
  required bool useApiKey,
}) {
  if (address.trim().isEmpty) {
    throw const FormatException('Enter the address of the server.');
  }
  final baseUrl = normaliseBaseUrl(address);
  final local = localAddress.trim();
  final localUrl = local.isEmpty
      ? null
      : normaliseBaseUrl(local.contains('://') ? local : 'http://$local');
  final name = username.trim();
  if (name.isEmpty) throw const FormatException('Enter the username.');
  final sameUser = name == current.username;

  if (useApiKey) {
    final key = apiKey.trim();
    if (key.isEmpty && (current.apiKey == null || !sameUser)) {
      throw const FormatException('Enter the API key.');
    }
    return ServerCredentials(
      baseUrl: baseUrl,
      username: name,
      apiKey: key.isEmpty ? current.apiKey : key,
      localUrl: localUrl,
    );
  }
  if (password.isEmpty) {
    if (current.apiKey != null || !sameUser) {
      throw const FormatException('Enter the password.');
    }
    return ServerCredentials(
      baseUrl: baseUrl,
      username: name,
      token: current.token,
      salt: current.salt,
      localUrl: localUrl,
    );
  }
  final fresh = ServerCredentials.fromPassword(
    baseUrl: baseUrl,
    username: name,
    password: password,
  );
  return ServerCredentials(
    baseUrl: fresh.baseUrl,
    username: name,
    token: fresh.token,
    salt: fresh.salt,
    localUrl: localUrl,
  );
}

/// The status line under "Scan library".
String scanStatusLabel(ScanStatus? status) {
  if (status == null) return 'Finds new and changed music on the server';
  final count = status.count;
  if (status.scanning) {
    return count == null ? 'Scanning…' : 'Scanning… $count songs so far';
  }
  final last = status.lastScan;
  return [
    if (last != null) 'Last scan ${_dateTime(last)}',
    if (count != null) '$count songs',
  ].join(' · ').ifEmpty('Finds new and changed music on the server');
}

String _dateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
