import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

/// Keeps customized hues readable on the light efficiency panels.
Color metricsTextColor(Color color) {
  if (AppPalette.dark) return color;
  // The darkest light panel uses a black overlay of 10%, inside a 2.5% tint.
  final background = Color.alphaBlend(
    Colors.black.withValues(alpha: 0.13), AppPalette.surface);
  for (var step = 0; step <= 100; step++) {
    final candidate = Color.lerp(color.withValues(alpha: 1), Colors.black, step / 100)!;
    final foreground = candidate.computeLuminance();
    final surface = background.computeLuminance();
    final ratio = (foreground > surface)
        ? (foreground + 0.05) / (surface + 0.05)
        : (surface + 0.05) / (foreground + 0.05);
    if (ratio >= 4.5) return candidate;
  }
  return Colors.black;
}
