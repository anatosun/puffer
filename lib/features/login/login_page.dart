import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../../ui/theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  bool _useApiKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_url, _username, _password, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final credentials = _useApiKey
        ? ServerCredentials(
            baseUrl: normaliseBaseUrl(_url.text),
            username: _username.text.trim(),
            apiKey: _apiKey.text.trim(),
          )
        : ServerCredentials.fromPassword(
            baseUrl: _url.text,
            username: _username.text.trim(),
            password: _password.text,
          );
    try {
      await ref.read(credentialsProvider.notifier).signIn(credentials);
    } on SubsonicException catch (e) {
      setState(
        () => _error = e.code == 40 ? 'Wrong username or password.' : e.message,
      );
    } on Exception catch (e) {
      setState(() => _error = 'Cannot reach the server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  const Icon(Icons.graphic_eq, size: 64, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to your server',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subsonic, OpenSubsonic, Navidrome, Gonic, …',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.url],
                    decoration: const InputDecoration(
                      labelText: 'Server address',
                      hintText: 'https://music.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  if (_useApiKey)
                    TextField(
                      controller: _apiKey,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API key'),
                    )
                  else
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _submit(),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use an API key'),
                    value: _useApiKey,
                    onChanged: (v) => setState(() => _useApiKey = v),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
