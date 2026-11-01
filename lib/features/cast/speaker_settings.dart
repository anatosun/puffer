import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sendspin_providers.dart';
import '../../sendspin/session.dart';
import '../../ui/messages.dart';

/// The phone as a Sendspin speaker of Music Assistant. It needs no sign-in: Music Assistant finds the phone on the local network.
class SpeakerSettings extends ConsumerWidget {
  const SpeakerSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sendspinEnabledProvider);
    final name = ref.watch(sendspinNameProvider);
    final status =
        ref.watch(sendspinStatusProvider).value ?? const SendspinStatus();
    final token = ref.watch(sendspinServiceProvider).value?.pairingToken;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Play as a speaker'),
          subtitle: const Text(
            'Music Assistant can play on this phone in sync with your other speakers, over Sendspin.',
          ),
          value: enabled,
          onChanged: (v) => ref.read(sendspinEnabledProvider.notifier).set(v),
        ),
        if (enabled) ...[
          ListTile(
            title: const Text('Speaker name'),
            subtitle: Text(name),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final controller = TextEditingController(text: name);
              final value = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Speaker name'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: (v) => Navigator.pop(context, v),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (value != null) {
                await ref.read(sendspinNameProvider.notifier).set(value);
              }
            },
          ),
          ListTile(
            leading: Icon(
              status.connected ? Icons.check_circle : Icons.wifi_tethering,
              color: status.connected ? Colors.green : null,
            ),
            title: Text(
              status.connected
                  ? 'Connected to ${status.serverName ?? 'Music Assistant'}'
                  : 'Waiting for Music Assistant',
            ),
            subtitle: Text(
              status.connected
                  ? [
                      status.paired ? 'Paired' : 'Not paired',
                      if (status.groupName != null) 'Group ${status.groupName}',
                      if (status.playing) 'playing',
                    ].join(' · ')
                  : 'Music Assistant finds the phone on the local network.',
            ),
          ),
          if (token != null)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Pairing token'),
              subtitle: Text(
                'Paste it into the settings of the "$name" player in Music Assistant, under Setup, for a secure connection.',
              ),
              trailing: IconButton(
                tooltip: 'Copy pairing token',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  showMessage('Pairing token copied');
                },
              ),
            ),
        ],
      ],
    );
  }
}
