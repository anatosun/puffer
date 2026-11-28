import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../ui/theme.dart';
import '../cast/music_assistant_page.dart';

/// The step of the first setup after the Subsonic server: signing in to Music Assistant, or skipping it. Either way it does not come back; Settings → Music Assistant signs in later.
class MusicAssistantSetupPage extends ConsumerWidget {
  const MusicAssistantSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void done() {
      ref.read(maSetupOfferedProvider.notifier).set(true);
      context.go('/home');
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: done, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Text(
                  'Play on your speakers',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Optional. You can sign in later in Settings → Music Assistant.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted),
                  ),
                ),
                Expanded(
                  child: MusicAssistantSignIn(
                    onSignedIn: done,
                    speakerSettings: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
