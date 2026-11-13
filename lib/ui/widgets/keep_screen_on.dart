import 'package:flutter/widgets.dart';

import '../../core/screen_awake.dart';

/// Keeps the screen on while [active] is true and [child] is in sight. A page covered by another stops its tickers, and so lets the screen sleep.
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  bool _holding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(KeepScreenOn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final want = widget.active && TickerMode.valuesOf(context).enabled;
    if (want == _holding) return;
    _holding = want;
    want ? ScreenAwake.instance.hold() : ScreenAwake.instance.release();
  }

  @override
  void dispose() {
    if (_holding) ScreenAwake.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
