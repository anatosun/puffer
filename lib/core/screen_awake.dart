import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while at least one part of the app holds it, such as the lyrics while a song plays, and lets it sleep once the last lets go. The system is told only when the count moves between zero and one, so parts that hold the screen at once do not undo each other.
class ScreenAwake {
  ScreenAwake([Future<void> Function(bool on)? apply])
    : _apply = apply ?? ((on) => WakelockPlus.toggle(enable: on));

  /// The one the app uses.
  static final instance = ScreenAwake();

  final Future<void> Function(bool on) _apply;
  int _holds = 0;

  bool get on => _holds > 0;

  void hold() {
    if (_holds++ == 0) _send(true);
  }

  void release() {
    if (_holds == 0) return;
    if (--_holds == 0) _send(false);
  }

  void _send(bool on) {
    // A platform without a wake lock leaves the screen to its own timeout.
    _apply(on).catchError((Object _) {});
  }
}
