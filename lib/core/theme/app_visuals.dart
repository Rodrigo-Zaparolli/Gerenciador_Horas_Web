import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Shared presentation only; never changes data or action callbacks.
class AppVisuals {
  AppVisuals._();
  static const cardRadius = 14.0;
  static const buttonRadius = 10.0;
  static const buttonHeight = 40.0;
  static const cardPadding = EdgeInsets.all(12);
  static Color get divider => AppPalette.border.withValues(alpha: 0.55);
  static List<BoxShadow> get shadows => [
        BoxShadow(
          color: Colors.black.withValues(alpha: AppPalette.dark ? 0.14 : 0.045),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
  static BoxDecoration get card => BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: divider),
      );
}
