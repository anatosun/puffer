import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../data/music_assistant/ma_client.dart';

class MusicAssistantPage extends ConsumerWidget {
  const MusicAssistantPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentials = ref.watch(maCredentialsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Music Assistant')),
      body: credentials == null ? const _SignIn() : _Connected(credentials),
    );
  }
}

class _SignIn extends ConsumerStatefulWidget {
  const _SignIn();

  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  bool _useToken = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_url, _username, _password, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(maCredentialsProvider.notifier);
    try {
      _useToken
          ? await notifier.signInWithToken(url: _url.text, token: _token.text)
          : await notifier.signIn(
              url: _url.text,
              username: _username.text.trim(),
              password: _password.text,
            );
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Music Assistant plays your music on speakers in sync over Sendspin, AirPlay, Chromecast and more. Puffer sends it what to play.',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Server address',
          hintText: 'homeassistant.local:8095',
        ),
      ),
      const SizedBox(height: 12),
      if (_useToken)
        TextField(
          controller: _token,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Long-lived access token',
          ),
        )
      else ...[
        TextField(
          controller: _username,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _submit(),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use an access token'),
        subtitle: const Text(
          'Create one in Music Assistant under your profile',
        ),
        value: _useToken,
        onChanged: (v) => setState(() => _useToken = v),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Connect'),
      ),
    ],
  );
}

class _Connected extends ConsumerWidget {
  const _Connected(this.credentials);

  final MaCredentials credentials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(maStatusProvider).value ?? MaConnectionStatus.disconnected;
    final client = ref.watch(maClientProvider);
    final providers = ref.watch(maSubsonicProvidersProvider);
    final choice = ref.watch(maProviderChoiceProvider);
    final instance = ref.watch(maSubsonicInstanceProvider);
    final version = client?.serverInfo?['server_version'] as String?;

    return ListView(
      children: [
        ListTile(
          leading: Icon(
            switch (status) {
              MaConnectionStatus.connected => Icons.check_circle,
              MaConnectionStatus.connecting => Icons.sync,
              _ => Icons.error_outline,
            },
            color: status == MaConnectionStatus.connected
                ? Colors.greenAccent
                : Colors.orangeAccent,
          ),
          title: Text(credentials.baseUrl.toString()),
          subtitle: Text(switch (status) {
            MaConnectionStatus.connected =>
              'Connected${version == null ? '' : ' · version $version'}',
            MaConnectionStatus.connecting => 'Connecting…',
            MaConnectionStatus.unauthorized =>
              'The access token is invalid or expired. Sign in again.',
            MaConnectionStatus.disconnected =>
              'Not reachable. Puffer retries in the background.',
          }),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            'HOW TRACKS ARE SENT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            instance == null
                ? 'As stream URLs of your Subsonic server. Add the same server to Music Assistant as an OpenSubsonic provider for full metadata and gapless playback.'
                : 'Through the OpenSubsonic provider of Music Assistant.',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
        RadioGroup<String>(
          groupValue: choice ?? instance ?? 'url',
          onChanged: (v) => ref.read(maProviderChoiceProvider.notifier).set(v),
          child: Column(
            children: [
              for (final p in providers.value ?? const [])
                RadioListTile<String>(
                  value: p.instanceId,
                  title: Text(p.name),
                  subtitle: Text(p.instanceId),
                ),
              const RadioListTile<String>(
                value: 'url',
                title: Text('Stream URLs'),
              ),
            ],
          ),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text(
            'Disconnect',
            style: TextStyle(color: Colors.redAccent),
          ),
          onTap: () => ref.read(maCredentialsProvider.notifier).signOut(),
        ),
      ],
    );
  }
}
