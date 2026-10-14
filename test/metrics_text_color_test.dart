import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/features/metrics/metrics_text_color.dart';

void main() {
  tearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
  for (final theme in AppVisualTheme.values) {
    test('efficiency text contrast for $theme', () {
      AppAppearance.instance.value = theme;
      for (final color in [const Color(0xFF19C37D), Colors.greenAccent, Colors.amber, Colors.redAccent, const Color(0xFF172B43), const Color(0xFF435970)]) {
        final text = metricsTextColor(color);
        for (final bg in [AppPalette.surface,
          Color.alphaBlend(Colors.black.withValues(alpha: 0.13), AppPalette.surface),
          Color.alphaBlend(AppPalette.text.withValues(alpha: 0.08), AppPalette.surface)]) {
          expect(AppPalette.contrast(text, bg), greaterThanOrEqualTo(4.5));
        }
      }
    });
  }
}
