import 'package:flutter/widgets.dart';

/// Draws [child] [scale] times larger: it lays out in a window smaller by that factor and is then stretched to fill the real one, so text, icons, touch targets and the breakpoints of the layout all follow. Images decode at the higher pixel ratio, so they stay sharp. At a scale of one it costs one identity transform; its structure never changes with the scale, so the pages keep their state when it does.
class InterfaceScale extends StatelessWidget {
  const InterfaceScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    EdgeInsets down(EdgeInsets insets) => insets / scale;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: media.size / scale,
        child: MediaQuery(
          data: media.copyWith(
            size: media.size / scale,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: down(media.padding),
            viewPadding: down(media.viewPadding),
            viewInsets: down(media.viewInsets),
            systemGestureInsets: down(media.systemGestureInsets),
          ),
          child: child,
        ),
      ),
    );
  }
}
