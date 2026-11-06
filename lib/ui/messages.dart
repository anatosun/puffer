import 'package:flutter/material.dart';

/// Shows snack bars from code without a [BuildContext], such as playback commands.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows [message], with a button labelled [action] that calls [onAction] when both are given.
void showMessage(String message, {String? action, VoidCallback? onAction}) =>
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null || onAction == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction),
      ),
    );

/// Runs a playback command and shows its failure instead of leaving it unhandled.
Future<void> runPlayback(Future<void> Function() command) async {
  try {
    await command();
  } on Exception catch (e) {
    showMessage('$e');
  }
}
