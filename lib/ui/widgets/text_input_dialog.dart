import 'package:flutter/material.dart';

/// Asks for one line of text, with [initial] filled in. Null when the person cancels; otherwise the text without surrounding spaces.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? label,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _TextInputDialog(title: title, initial: initial, label: label),
);

/// The dialog of [askText]. It owns its controller, which it disposes once the dialog has left the screen; disposing it when the result arrives would break the closing animation, which still draws the field.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    this.label,
  });

  final String title;
  final String initial;
  final String? label;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
