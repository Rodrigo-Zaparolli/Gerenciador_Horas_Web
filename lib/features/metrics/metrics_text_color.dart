import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

Color metricsTextColor(Color color) {
  final backgrounds = [AppPalette.surface,
    Color.alphaBlend(Colors.black.withValues(alpha: 0.13), AppPalette.surface),
    Color.alphaBlend(AppPalette.text.withValues(alpha: 0.08), AppPalette.surface)];
  var result = color;
  for (final background in backgrounds) {
    result = AppPalette.readableText(result, background: background);
  }
  return result;
}
