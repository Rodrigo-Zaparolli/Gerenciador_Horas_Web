import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';

void main() {
  tearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
  for (final theme in AppVisualTheme.values) {
    test('readable surfaces and actual button backgrounds for $theme', () {
      AppAppearance.instance.value = theme;
      for (final bg in [AppPalette.surface, AppPalette.field, AppPalette.header,
        AppPalette.background, AppPalette.raised]) {
        expect(AppPalette.contrast(AppPalette.text, bg), greaterThanOrEqualTo(4.5));
        expect(AppPalette.contrast(AppPalette.secondary, bg), greaterThanOrEqualTo(4.5));
      }
      for (final bg in [AppPalette.primary, AppPalette.accent, AppPalette.surface,
        AppPalette.background, AppPalette.success, AppPalette.warning, AppPalette.danger,
        const Color(0xFF35D27F)]) {
        expect(AppPalette.contrast(AppPalette.foregroundOn(bg), bg), greaterThanOrEqualTo(4.5));
      }
      final material = AppPalette.dark ? AppTheme.dark : AppTheme.light;
      expect(AppPalette.contrast(material.colorScheme.onPrimary, material.colorScheme.primary), greaterThanOrEqualTo(4.5));
    });
  }
}
