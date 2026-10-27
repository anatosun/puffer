import 'package:flutter/material.dart';

/// A light that sweeps across its child, for the outlines shown while content loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final light = Color.lerp(
      base,
      Theme.of(context).colorScheme.onSurface,
      0.08,
    )!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [base, light, base],
          stops: const [0.35, 0.5, 0.65],
          begin: Alignment(-2 + 4 * _controller.value, -0.3),
          end: Alignment(-1 + 4 * _controller.value, 0.3),
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// The outline of a row of cards of [width].
class ShelfPlaceholder extends StatelessWidget {
  const ShelfPlaceholder({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Box(width: width, height: width),
          const SizedBox(height: 8),
          _Box(width: width * 0.8, height: 12),
          const SizedBox(height: 6),
          _Box(width: width * 0.5, height: 10),
        ],
      ),
    ),
  );
}

/// The outline of a list of rows.
class ListPlaceholder extends StatelessWidget {
  const ListPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const _Box(width: 44, height: 44, radius: 4),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.4 + (i % 3) * 0.15,
                    child: const _Box(height: 12),
                  ),
                  const SizedBox(height: 6),
                  const FractionallySizedBox(
                    widthFactor: 0.3,
                    child: _Box(height: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
