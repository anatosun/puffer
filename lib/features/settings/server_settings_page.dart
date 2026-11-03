import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/backdrop.dart';
import 'server_settings.dart';
import 'settings_section.dart';

class ServerSettingsPage extends ConsumerWidget {
  const ServerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentials = ref.watch(credentialsProvider);
    final offline = ref.watch(isOfflineProvider);
    final info = ref.watch(serverInfoProvider);
    final active = ref.watch(activeAddressProvider);
    final extensions = ref.watch(clientProvider)?.extensions ?? const {};
    final refresh = ref.watch(cacheRefreshProvider);
    if (credentials == null) return const SizedBox.shrink();

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Server')),
        body: ListView(
          children: [
            const SettingsSection('Connection'),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(credentials.baseUrl),
              subtitle: Text(
                [
                  credentials.username,
                  if (credentials.apiKey != null) 'API key',
                ].join(' · '),
              ),
            ),
            if (credentials.localUrl case final local?)
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(local),
                subtitle: Text(
                  active == local
                      ? 'Local address · in use'
                      : 'Local address · used on the home network',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit connection'),
              subtitle: const Text(
                'Address, local address and sign-in, without losing downloads',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/server/connection'),
            ),
            ListTile(
              leading: const Icon(Icons.network_check),
              title: const Text('Test connection'),
              subtitle: Text(switch (info) {
                _ when offline => 'Offline',
                AsyncData(value: final i?) =>
                  'Answered in ${i.responseTime.inMilliseconds} ms',
                AsyncError(:final error) => _errorText(error),
                _ => 'Testing…',
              }),
              onTap: offline ? null : () => ref.invalidate(serverInfoProvider),
            ),
            const SettingsSection('About the server'),
            ListTile(
              title: const Text('Software'),
              subtitle: Text(
                info.value?.server ?? (offline ? 'Offline' : 'Not reported'),
              ),
            ),
            ListTile(
              title: const Text('Subsonic API'),
              subtitle: Text(
                [
                  if (info.value case final i?) i.apiVersion,
                  if (info.value?.openSubsonic ?? false) 'OpenSubsonic',
                ].join(' · ').ifEmptyDash,
              ),
            ),
            if (extensions.isNotEmpty)
              ExpansionTile(
                title: const Text('OpenSubsonic extensions'),
                subtitle: Text('${extensions.length}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in extensions.toList()..sort())
                        Chip(label: Text(e)),
                    ],
                  ),
                ],
              ),
            const SettingsSection('External sources'),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_download_outlined),
              title: const Text('Skip external songs in the background'),
              subtitle: const Text(
                'Songs a proxy like octo-fiesta fetches from outside your library are left out',
              ),
              value: !ref.watch(externalInBackgroundProvider),
              onChanged: (skip) =>
                  ref.read(externalInBackgroundProvider.notifier).set(!skip),
            ),
            const SettingsSection('Library'),
            if (!offline && (ref.watch(isAdminProvider).value ?? false))
              const _ScanTile(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh library cache'),
              subtitle: Text(
                refresh == null
                    ? 'Reloads artists, albums and playlists from the server. Downloads keep their details.'
                    : refresh.total == 0
                    ? 'Clearing…'
                    : 'Reloading downloaded items… ${refresh.done} of ${refresh.total}',
              ),
              trailing: refresh == null
                  ? null
                  : const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              onTap: offline || refresh != null
                  ? null
                  : () => _confirmRefresh(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRefresh(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refresh library cache?'),
        content: const Text(
          'The saved copy of the library is cleared and loads again from the server as you browse. Downloaded music stays and keeps working offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await ref.read(cacheRefreshProvider.notifier).run();
  }
}

class _ScanTile extends ConsumerWidget {
  const _ScanTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    final scanning = scan.value?.scanning ?? false;
    return ListTile(
      leading: const Icon(Icons.manage_search),
      title: const Text('Scan library'),
      subtitle: Text(switch (scan) {
        AsyncError(:final error) => _errorText(error),
        _ => scanStatusLabel(scan.value),
      }),
      trailing: scanning
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: scanning || scan.isLoading
          ? null
          : () => ref.read(scanProvider.notifier).start(),
    );
  }
}

String _errorText(Object error) => switch (error) {
  SubsonicException(code: 40) => 'Wrong username or password',
  SubsonicException(code: 50) => 'Not allowed for this user',
  SubsonicException(:final message) => message,
  _ => 'The server does not answer',
};

extension on String {
  String get ifEmptyDash => isEmpty ? '–' : this;
}

/// Edits the address, the local address and the sign-in of the server. Saving checks them against the server first.
class ConnectionSettingsPage extends ConsumerStatefulWidget {
  const ConnectionSettingsPage({super.key});

  @override
  ConsumerState<ConnectionSettingsPage> createState() =>
      _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState
    extends ConsumerState<ConnectionSettingsPage> {
  late final ServerCredentials _current = ref.read(credentialsProvider)!;
  late final _url = TextEditingController(text: _current.baseUrl);
  late final _local = TextEditingController(text: _current.localUrl ?? '');
  late final _username = TextEditingController(text: _current.username);
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  late bool _useApiKey = _current.apiKey != null;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_url, _local, _username, _password, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credentials = editedCredentials(
        _current,
        address: _url.text,
        localAddress: _local.text,
        username: _username.text,
        password: _password.text,
        apiKey: _apiKey.text,
        useApiKey: _useApiKey,
      );
      await ref
          .read(credentialsProvider.notifier)
          .updateConnection(credentials);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on SubsonicException catch (e) {
      setState(() => _error = _errorText(e));
    } on Exception catch (e) {
      setState(() => _error = 'Cannot reach the server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keepHint = _current.apiKey == null ? 'Leave empty to keep it' : null;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Edit connection')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'https://music.example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _local,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Local address (optional)',
                hintText: 'http://192.168.1.10:4533',
                helperText: 'Used on Wi-Fi when the server answers there, which is faster and works when the internet is down',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            if (_useApiKey)
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API key',
                  helperText: _current.apiKey != null
                      ? 'Leave empty to keep it'
                      : null,
                ),
              )
            else
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: keepHint,
                ),
                onSubmitted: (_) => _save(),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use an API key'),
              value: _useApiKey,
              onChanged: (v) => setState(() => _useApiKey = v),
            ),
            Text(
              'Downloads and the library cache stay. To connect to another server, sign out instead.',
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
