import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'app_visuals.dart';

class AppTheme {
  const AppTheme._();
  static const String caminhoFundo = 'assets/images/fundo.png';
  static const double opacidadeFundo = 0.35;
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static Color? get backgroundColor => null;

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    Color neutral(int light, int darkValue) {
      return AppPalette.resolve(Color(light), Color(darkValue), isDark: dark);
    }

    final background = neutral(0xFFD5DFE9, 0xFF0B1220);
    final surface = neutral(0xFFE2E8EF, 0xFF152235);
    final field = neutral(0xFFD3DEE9, 0xFF101B2D);
    final text = neutral(0xFF172B43, 0xFFE8EFF7);
    final secondary = neutral(0xFF435970, 0xFFABBBD0);
    final primary = neutral(0xFF096AB5, 0xFF38BDF8);
    final border = neutral(0xFFAFBFD0, 0xFF33465D);
    final scheme = ColorScheme.fromSeed(
            seedColor: primary, brightness: brightness)
        .copyWith(
            primary: primary,
            onPrimary: AppPalette.foregroundForPrimary(primary, isDark: dark),
            secondary: neutral(0xFF08768C, 0xFF22D3EE),
            surface: surface,
            onSurface: text,
            onSurfaceVariant: secondary,
            outline: border,
            outlineVariant: border.withValues(alpha: 0.6),
            surfaceContainerHighest: field);
    final base = ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        fontFamily: 'Segoe UI',
        visualDensity: VisualDensity.standard);
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppVisuals.buttonRadius));
    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: color));
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerColor: border.withValues(alpha: 0.65),
      iconTheme: IconThemeData(color: secondary, size: 20),
      appBarTheme: AppBarTheme(
          backgroundColor: surface,
          foregroundColor: text,
          elevation: 0,
          scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppVisuals.cardRadius),
              side: BorderSide(color: border.withValues(alpha: 0.55)))),
      dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          contentTextStyle:
              TextStyle(color: secondary, fontSize: 13, height: 1.45),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: TextStyle(
              color: text, fontSize: 20, fontWeight: FontWeight.w600)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: field,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          hintStyle: TextStyle(color: secondary, fontSize: 13),
          labelStyle: TextStyle(color: secondary),
          border: inputBorder(border),
          enabledBorder: inputBorder(border),
          focusedBorder: inputBorder(primary),
          errorBorder: inputBorder(scheme.error)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              iconSize: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: shape,
              minimumSize: const Size(0, 40),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              iconSize: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 0,
              shape: shape,
              backgroundColor: primary,
              foregroundColor: scheme.onPrimary,
              minimumSize: const Size(0, 40),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              iconSize: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: shape,
              foregroundColor: primary,
              side: BorderSide(color: border),
              minimumSize: const Size(0, 40))),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          iconSize: 18,
          minimumSize: const Size(0, 40),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          shape: shape,
          textStyle: TextStyle(color: text, fontSize: 13)),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface, surfaceTintColor: Colors.transparent),
      dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(field),
          dividerThickness: 0.7,
          horizontalMargin: 16,
          headingTextStyle: TextStyle(
              color: secondary, fontSize: 12, fontWeight: FontWeight.w600),
          dataTextStyle: TextStyle(color: text, fontSize: 12)),
      scrollbarTheme: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(7),
          radius: const Radius.circular(6),
          thumbColor: WidgetStatePropertyAll(secondary.withValues(alpha: 0.4))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF172B43),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: shape),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
              color: const Color(0xFF172B43),
              borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
