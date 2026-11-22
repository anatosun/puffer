import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';

/// One line of text that, when it is too long for its room, scrolls to show the rest every few seconds and comes back round to the start. Text that fits stays still, and nothing runs between passes or while the app is hidden: a timer starts each pass, and only the pass itself animates.
class MarqueeText extends ConsumerStatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle? style;

  /// Where the text sits while it fits.
  final TextAlign textAlign;

  /// How long the text stays still before each pass.
  static const pause = Duration(seconds: 3);

  /// The speed of a pass, in logical pixels per second.
  static const speed = 40.0;

  /// The space between the end of the text and its next copy.
  static const gap = 48.0;

  @override
  ConsumerState<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends ConsumerState<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // The copy now stands where the text began, so the jump back does not show.
        _controller.value = 0;
        _schedule();
      }
    });
  Timer? _timer;

  /// The width of the text, measured once per text, style and text scale.
  double? _width;
  double _height = 0;
  Object? _measured;

  /// Whether the text is wider than its room, as the last layout found.
  bool _overflows = false;

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) _stop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Ends the pass and its timer. It leaves the offset alone, since it can run while widgets build; the next pass starts from the beginning.
  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_controller.isAnimating) _controller.stop();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(MarqueeText.pause, () {
      _timer = null;
      if (!mounted || !_overflows) return;
      final distance = (_width ?? 0) + MarqueeText.gap;
      _controller.duration = Duration(
        milliseconds: (distance / MarqueeText.speed * 1000).round(),
      );
      _controller.forward(from: 0);
    });
  }

  void _measure(TextStyle style, TextScaler scaler, TextDirection direction) {
    final key = (widget.text, style, scaler, direction);
    if (key == _measured) return;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    _width = painter.width;
    _height = painter.height;
    painter.dispose();
    _measured = key;
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(appVisibleProvider);
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    _measure(
      style,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final overflows = _width! > box.maxWidth;
        _overflows = overflows;
        if (!overflows || !visible) {
          _stop();
        } else if (_timer == null && !_controller.isAnimating) {
          _schedule();
        }
        if (!overflows) {
          return Text(
            widget.text,
            textAlign: widget.textAlign,
            maxLines: 1,
            style: widget.style,
          );
        }
        final line = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        return Semantics(
          label: widget.text,
          excludeSemantics: true,
          child: SizedBox(
            width: box.maxWidth,
            height: _height,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      -_controller.value * (_width! + MarqueeText.gap),
                      0,
                    ),
                    child: child,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      line,
                      const SizedBox(width: MarqueeText.gap),
                      line,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
