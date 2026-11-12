import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_mark.dart';

/// A cover made of [title] in large type and the pufferfish, on the colours of the theme. The type and the mark grow with the cover, which fills [size] or, without one, the space it gets.
class TitleCover extends StatelessWidget {
  const TitleCover(this.title, {super.key, this.size, this.radius = 4});

  final String title;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final ink = colours.onPrimaryContainer;
    return SizedBox.square(
      dimension: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final inset = side * 0.09;
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colours.primaryContainer, colours.tertiaryContainer],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      // The size follows the cover and not the text size of the system, as on printed artwork.
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: ink,
                        fontSize: side * 0.15,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: BrandMark(
                        size: side * 0.26,
                        color: ink.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
