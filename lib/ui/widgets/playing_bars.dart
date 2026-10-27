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

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) _controller.repeat();
    if (!widget.playing && _controller.isAnimating) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
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
                                          (_controller.value + i * 0.29) *
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
    ),
  );
}
