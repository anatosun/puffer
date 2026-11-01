import 'package:flutter/material.dart';

/// The Puffer mark, tinted with [color] or the theme's foreground colour, so it suits light and dark themes. It is the detailed mark, meant for 64 pixels and up.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/puffer-mark-white-512.png',
    width: size,
    height: size,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    semanticLabel: 'Puffer',
  );
}
