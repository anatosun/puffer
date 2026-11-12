import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Three bars that bounce while [playing] and rest while paused, marking the track that plays.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 16,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> {
  /// The bars move 15 times a second, which looks smooth at their size. An animation would redraw the screen on every frame the display shows, up to 120 times a second.
  static const _step = Duration(milliseconds: 66);
  static const _period = 1200;

  final _clock = Stopwatch();
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _update());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Off for pages under another page, as for an animation.
    _shown = TickerMode.valuesOf(context).enabled;
    _update();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    _update();
  }

  /// Runs the clock while the song plays and the bars show, in an app that shows.
  void _update() {
    final visible = switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      _ => false,
    };
    final run = widget.playing && _shown && visible;
    if (run && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(_step, (_) => setState(() {}));
    } else if (!run && _timer != null) {
      _clock.stop();
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _clock.elapsedMilliseconds % _period / _period;
    return SizedBox.square(
      dimension: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: widget.size / 4.5,
              // Each bar follows its own phase; at rest the bars keep a low, uneven profile.
              height:
                  widget.size *
                  (0.3 +
                      0.7 *
                          (widget.playing
                              ? (sin(
                                          (phase + i * 0.29) *
                                              2 *
                                              pi *
                                              (1 + i * 0.4),
                                        ) +
                                        1) /
                                    2
                              : [0.4, 0.8, 0.6][i] * 0.6)),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}
