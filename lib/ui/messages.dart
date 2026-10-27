import 'package:flutter/material.dart';

/// Shows snack bars from code without a [BuildContext], such as playback commands.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void showMessage(String message) =>
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));

/// Runs a playback command and shows its failure instead of leaving it unhandled.
Future<void> runPlayback(Future<void> Function() command) async {
  try {
    await command();
  } on Exception catch (e) {
    showMessage('$e');
  }
}
