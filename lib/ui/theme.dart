import 'package:flutter/material.dart';

const accent = Color(0xFFE5A00D);

/// Black in dark mode and white in light mode, coloured by [seed], the amber of Plexamp unless the person picks another accent.
ThemeData buildTheme(Brightness brightness, {Color seed = accent}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? Colors.black : Colors.white;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      .copyWith(
        surface: background,
        onSurface: dark ? Colors.white : Colors.black,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    canvasColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      height: 60,
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      showDragHandle: true,
    ),
  );
}

/// Text and icon shades derived from the theme, so they read in both modes.
extension ThemeShades on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  Color get background => Theme.of(this).scaffoldBackgroundColor;
  Color get muted => colors.onSurface.withValues(alpha: 0.6);
  Color get faint => colors.onSurface.withValues(alpha: 0.4);
  Color get subtle => colors.onSurface.withValues(alpha: 0.24);
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit < 2 ? 0 : 1)} ${units[unit]}';
}
