import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'launch_animation.dart';

/// Shows [PufferLaunchAnimation] over [child] when the app starts cold, then fades it out over 250 ms once it ends. A tap skips it. Start-up work runs before the first frame, so nothing waits for the animation; returning from the background keeps this widget, so it does not play again.
class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Off in tests and wherever the animation should not show.
  final bool enabled;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  late bool _showing = widget.enabled;
  bool _fading = false;

  void _finish() {
    if (!_fading && mounted) setState(() => _fading = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showing) return widget.child;
    final size = MediaQuery.sizeOf(context);
    // The mark fills about half the shorter side, as on the 1080 × 1920 reference stage (520 px).
    final markSize = (math.min(size.width, size.height) * 0.48).clamp(
      120.0,
      280.0,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          onEnd: () {
            if (_fading && mounted) setState(() => _showing = false);
          },
          // The gate sits above the screens, outside any Material, which the wordmark needs for its text style.
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: Semantics(
                label: 'Puffer',
                hint: 'Tap to skip',
                child: PufferLaunchAnimation(
                  markSize: markSize,
                  onFinished: _finish,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
