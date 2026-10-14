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
      for (final color in [const Color(0xFF19C37D), Colors.greenAccent, Colors.amber, Colors.redAccent]) {
        final text = metricsTextColor(color);
        if (AppPalette.dark) {
          expect(text, color);
        } else {
          for (final alpha in [0.0, 0.10, 0.13]) {
            final bg = Color.alphaBlend(Colors.black.withValues(alpha: alpha), AppPalette.surface);
            final contrast = (bg.computeLuminance() + 0.05) / (text.computeLuminance() + 0.05);
            expect(contrast, greaterThanOrEqualTo(4.5));
          }
        }
      }
    });
  }
}
