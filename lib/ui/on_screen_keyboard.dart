import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Replaces the selection of [value] with [text], or inserts it at the end when the field has no selection yet.
TextEditingValue insertText(TextEditingValue value, String text) {
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final start = selection.start, end = selection.end;
  return TextEditingValue(
    text: value.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// Deletes the selection of [value], or the character before the cursor, counting a character as the person sees it, so an emoji goes in one press.
TextEditingValue deleteBackward(TextEditingValue value) {
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  if (!selection.isCollapsed) return insertText(value, '');
  final before = value.text.substring(0, selection.start);
  if (before.isEmpty) return value;
  final kept = before.characters.skipLast(1).toString();
  return TextEditingValue(
    text: kept + value.text.substring(selection.start),
    selection: TextSelection.collapsed(offset: kept.length),
  );
}

/// The keyboard of the app on a touchscreen without a keyboard of its own, such as a Raspberry Pi kiosk. A physical keyboard keeps working beside it, since the framework keeps the platform input informed of every change.
class OnScreenKeyboardControl with TextInputControl {
  /// Whether the keyboard shows. A text field asks for it when it gains the focus and lets it go when it loses it.
  final visible = ValueNotifier(false);

  /// The configuration of the text field that has the focus: its action and its kind of input.
  final configuration = ValueNotifier<TextInputConfiguration?>(null);

  TextInputClient? _client;
  TextEditingValue _value = TextEditingValue.empty;

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    this.configuration.value = configuration;
  }

  @override
  void detach(TextInputClient client) {
    if (_client != client) return;
    _client = null;
    configuration.value = null;
    visible.value = false;
  }

  @override
  void updateConfig(TextInputConfiguration configuration) =>
      this.configuration.value = configuration;

  @override
  void setEditingState(TextEditingValue value) => _value = value;

  @override
  void show() => visible.value = _client != null;

  @override
  void hide() => visible.value = false;

  void _edit(TextEditingValue value) {
    _value = value;
    TextInput.updateEditingValue(value);
  }

  void type(String text) => _edit(insertText(_value, text));

  void backspace() => _edit(deleteBackward(_value));

  /// The key at the bottom right: a new line in a field of several lines, the action of the field otherwise.
  void enter() {
    final action = configuration.value?.inputAction ?? TextInputAction.done;
    if (action == TextInputAction.newline) {
      type('\n');
    } else {
      _client?.performAction(action);
    }
  }

  void dispose() {
    visible.dispose();
    configuration.dispose();
  }
}

/// Shows [OnScreenKeyboard] at the bottom of the window while a text field has the focus and [enabled] is set. The pages above it learn its height through the bottom inset of [MediaQuery], as from the keyboard of a phone.
class OnScreenKeyboardHost extends StatefulWidget {
  const OnScreenKeyboardHost({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<OnScreenKeyboardHost> createState() => _OnScreenKeyboardHostState();
}

class _OnScreenKeyboardHostState extends State<OnScreenKeyboardHost> {
  final _control = OnScreenKeyboardControl();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) TextInput.setInputControl(_control);
  }

  @override
  void didUpdateWidget(OnScreenKeyboardHost old) {
    super.didUpdateWidget(old);
    if (widget.enabled == old.enabled) return;
    if (widget.enabled) {
      TextInput.setInputControl(_control);
    } else {
      _control.hide();
      TextInput.restorePlatformInputControl();
    }
  }

  @override
  void dispose() {
    if (widget.enabled) TextInput.restorePlatformInputControl();
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _control.visible,
    builder: (context, visible, child) {
      final media = MediaQuery.of(context);
      final height = visible ? OnScreenKeyboard.heightFor(media.size) : 0.0;
      return Stack(
        children: [
          // The first child keeps its place whether the keyboard shows or not, so the pages keep their state.
          MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(
                bottom: height + media.viewPadding.bottom,
              ),
            ),
            child: child!,
          ),
          if (visible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: OnScreenKeyboard(control: _control, height: height),
            ),
        ],
      );
    },
    child: widget.child,
  );
}

enum _Layer { letters, symbols, more }

enum _Shift { off, once, locked }

/// A QWERTY keyboard with a layer of digits and symbols and a second layer of rarer symbols, enough for a server address, a password and a search.
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({
    super.key,
    required this.control,
    required this.height,
  });

  final OnScreenKeyboardControl control;
  final double height;

  static const _rows = 4;
  static const _padding = 6.0;

  /// The height of the keyboard on a screen of [size]: keys large enough to hit with a finger, and on a short screen no more than about two fifths of it.
  static double heightFor(Size size) {
    final row = (size.height * 0.095).clamp(36.0, 54.0);
    return row * _rows + _padding * 2;
  }

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  var _layer = _Layer.letters;
  var _shift = _Shift.off;

  static const _letters = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _symbols = ['1234567890', '@#\$%&-+()/', '*"\':;!?'];
  static const _more = ['[]{}<>^~|\\', '_`=€£¥•°§', '.,?!\''];

  void _type(String key) {
    widget.control.type(key);
    if (_shift == _Shift.once) setState(() => _shift = _Shift.off);
  }

  void _toggleShift() => setState(
    () => _shift = switch (_shift) {
      _Shift.off => _Shift.once,
      _Shift.once => _Shift.locked,
      _Shift.locked => _Shift.off,
    },
  );

  String _label(String key) => _layer == _Layer.letters && _shift != _Shift.off
      ? key.toUpperCase()
      : key;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final config = widget.control.configuration.value;
    final rows = switch (_layer) {
      _Layer.letters => _letters,
      _Layer.symbols => _symbols,
      _Layer.more => _more,
    };
    final keyHeight =
        (widget.height - OnScreenKeyboard._padding * 2) /
        OnScreenKeyboard._rows;
    // An address or an e-mail gets the character it needs most beside the space bar.
    final extra = switch (config?.inputType) {
      TextInputType.url => '/',
      TextInputType.emailAddress => '@',
      _ => ',',
    };
    Widget character(String key) =>
        _Key(label: _label(key), onPressed: () => _type(_label(key)));
    final enterIcon = switch (config?.inputAction) {
      TextInputAction.search => Icons.search,
      TextInputAction.newline => Icons.keyboard_return,
      TextInputAction.next => Icons.arrow_forward,
      TextInputAction.go || TextInputAction.send => Icons.send,
      _ => Icons.check,
    };

    return TextFieldTapRegion(
      // The keys never take the focus away from the text field they type into.
      child: ExcludeFocus(
        child: Material(
          color: colors.surfaceContainerHigh,
          child: SizedBox(
            height: widget.height,
            child: Padding(
              padding: const EdgeInsets.all(OnScreenKeyboard._padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      for (final (i, row) in rows.indexed)
                        SizedBox(
                          height: keyHeight,
                          child: Row(
                            children: [
                              if (i == 2)
                                _Key(
                                  flex: 3,
                                  icon: switch ((_layer, _shift)) {
                                    (_Layer.letters, _Shift.off) =>
                                      Icons.arrow_upward,
                                    (_Layer.letters, _Shift.once) =>
                                      Icons.arrow_upward,
                                    (_Layer.letters, _Shift.locked) =>
                                      Icons.keyboard_capslock,
                                    _ => null,
                                  },
                                  label: switch (_layer) {
                                    _Layer.letters => null,
                                    _Layer.symbols => '#+=',
                                    _Layer.more => '123',
                                  },
                                  highlighted:
                                      _layer == _Layer.letters &&
                                      _shift != _Shift.off,
                                  tooltip: _layer == _Layer.letters
                                      ? 'Shift'
                                      : null,
                                  onPressed: _layer == _Layer.letters
                                      ? _toggleShift
                                      : () => setState(
                                          () =>
                                              _layer = _layer == _Layer.symbols
                                              ? _Layer.more
                                              : _Layer.symbols,
                                        ),
                                ),
                              // The middle row of letters is shorter and sits centred, as on a physical keyboard.
                              if (i == 1 && row.length == 9) const Spacer(),
                              for (final key in row.split('')) character(key),
                              if (i == 1 && row.length == 9) const Spacer(),
                              if (i == 2)
                                _Key(
                                  flex: 3,
                                  icon: Icons.backspace_outlined,
                                  tooltip: 'Delete',
                                  repeat: true,
                                  onPressed: widget.control.backspace,
                                ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: keyHeight,
                        child: Row(
                          children: [
                            _Key(
                              flex: 3,
                              label: _layer == _Layer.letters ? '123' : 'ABC',
                              onPressed: () => setState(
                                () => _layer = _layer == _Layer.letters
                                    ? _Layer.symbols
                                    : _Layer.letters,
                              ),
                            ),
                            _Key(
                              flex: 2,
                              icon: Icons.keyboard_hide_outlined,
                              tooltip: 'Hide keyboard',
                              onPressed: widget.control.hide,
                            ),
                            _Key(
                              flex: 2,
                              label: extra,
                              onPressed: () => _type(extra),
                            ),
                            _Key(
                              flex: 10,
                              label: ' ',
                              onPressed: () => _type(' '),
                            ),
                            _Key(
                              flex: 2,
                              label: '.',
                              onPressed: () => _type('.'),
                            ),
                            _Key(
                              flex: 4,
                              icon: enterIcon,
                              highlighted: true,
                              onPressed: widget.control.enter,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    this.label,
    this.icon,
    this.flex = 2,
    this.highlighted = false,
    this.repeat = false,
    this.tooltip,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final int flex;
  final bool highlighted;

  /// Whether holding the key repeats it, as for the delete key.
  final bool repeat;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  /// Runs only while the key is held.
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = widget.highlighted
        ? colors.primary
        : colors.surfaceContainerHighest;
    final foreground = widget.highlighted ? colors.onPrimary : colors.onSurface;
    Widget key = Material(
      color: background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        canRequestFocus: false,
        onTap: widget.onPressed,
        onLongPress: widget.repeat
            ? () {
                widget.onPressed();
                _repeat = Timer.periodic(
                  const Duration(milliseconds: 70),
                  (_) => widget.onPressed(),
                );
              }
            : null,
        child: Center(
          child: widget.icon != null
              ? Icon(widget.icon, size: 20, color: foreground)
              : Text(
                  widget.label ?? '',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 18, color: foreground),
                ),
        ),
      ),
    );
    if (widget.repeat) {
      key = Listener(
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: key,
      );
    }
    if (widget.tooltip case final tooltip?) {
      key = Semantics(label: tooltip, button: true, child: key);
    }
    return Expanded(
      flex: widget.flex,
      child: Padding(padding: const EdgeInsets.all(3), child: key),
    );
  }
}
