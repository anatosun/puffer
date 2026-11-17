import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'layout.dart';

/// Where the mouse last pressed, so a menu opens next to the pointer. A touch clears it.
class PointerMemory {
  static Offset? lastMouseDown;
  static DateTime? _at;

  /// The place of a mouse press within the last second, which is the press that opened a menu.
  static Offset? get recentMouseDown {
    final at = _at;
    if (at == null ||
        DateTime.now().difference(at) > const Duration(seconds: 1)) {
      return null;
    }
    return lastMouseDown;
  }

  static void record(PointerDownEvent event) {
    lastMouseDown = event.kind == PointerDeviceKind.mouse
        ? event.position
        : null;
    _at = DateTime.now();
  }
}

/// Records [PointerMemory] for the whole app without taking any gesture.
class PointerRecorder extends StatelessWidget {
  const PointerRecorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: PointerMemory.record,
    child: child,
  );
}

/// A menu or sheet. On a phone it slides up from the bottom. In a wide window it opens next to the mouse pointer when the mouse opened it, and in the middle of the window otherwise or when it holds a long list ([isScrollControlled]), at most [width] wide.
Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  double width = 380,
}) {
  if (!isWide(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      builder: builder,
    );
  }
  final anchor = isScrollControlled ? null : PointerMemory.recentMouseDown;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: anchor == null ? Colors.black38 : Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(animation),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      final panel = Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isScrollControlled ? width * 1.5 : width,
            maxHeight: screen.height * (anchor == null ? 0.9 : 0.8),
          ),
          // Sheets size themselves by the screen; the panel takes their height and no more.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: Builder(builder: builder),
          ),
        ),
      );
      if (anchor == null) return Center(child: panel);
      return CustomSingleChildLayout(
        delegate: _NextToPointer(anchor),
        child: panel,
      );
    },
  );
}

/// Places a menu below and to the right of the pointer, and moves it back inside the window where it would leave it.
class _NextToPointer extends SingleChildLayoutDelegate {
  const _NextToPointer(this.pointer);

  final Offset pointer;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = pointer.dx;
    var y = pointer.dy;
    if (x + child.width > size.width - _margin) x = pointer.dx - child.width;
    if (y + child.height > size.height - _margin) {
      y = size.height - _margin - child.height;
    }
    return Offset(
      x.clamp(_margin, size.width - _margin - child.width),
      y.clamp(_margin, size.height - _margin - child.height),
    );
  }

  @override
  bool shouldRelayout(_NextToPointer old) => old.pointer != pointer;
}
