import 'package:flutter/material.dart';
import 'app_appearance.dart';

/// Semantic colors shared by legacy screens and Material components.
/// Document/Excel colors and status indicators are deliberately left intact.
class AppPalette {
  AppPalette._();
  static bool get dark => AppAppearance.instance.isDark;
  static final slateColors = {
    Color(0xFFD5DFE9): Color(0xFFA5B4C2),
    Color(0xFFE2E8EF): Color(0xFFD3E2EF),
    Color(0xFFD3DEE9): Color(0xFFBCCBD8),
    Color(0xFFCBD7E3): Color(0xFFBCCBD8),
    Color(0xFFDAE4EE): Color(0xFFC7D7E5),
    Color(0xFFAFBFD0): Color(0xFF8E9DAB),
    Color(0xFF096AB5): Color(0xFF606F7D),
    Color(0xFF08768C): Color(0xFF455A6B),
    Color(0xFF172B43): Color(0xFF172B43),
    Color(0xFF435970): Color(0xFF2D4355),
    Color(0xFF50647C): Color(0xFF344A5D),
  };
  static final oceanColors = {
    Color(0xFF0B1220): Color(0xFF15384A),
    Color(0xFF152235): Color(0xFF18435A),
    Color(0xFF101B2D): Color(0xFF123449),
    Color(0xFF203148): Color(0xFF225168),
    Color(0xFF33465D): Color(0xFF426777),
    Color(0xFF38BDF8): Color(0xFF81C5E8),
    Color(0xFF22D3EE): Color(0xFF95D3E8),
    Color(0xFFE8EFF7): Color(0xFFE7F3FA),
    Color(0xFFABBBD0): Color(0xFFBED5E3),
    Color(0xFF8FA4BC): Color(0xFFACC9DA),
  };
  static final azureColors = {
    Color(0xFFD5DFE9): Color(0xFFD3E2EF),
    Color(0xFFE2E8EF): Color(0xFFE3EEF6),
    Color(0xFFD3DEE9): Color(0xFFC5DDEE),
    Color(0xFFCBD7E3): Color(0xFFB8D3E6),
    Color(0xFFDAE4EE): Color(0xFFD5E7F4),
    Color(0xFFAFBFD0): Color(0xFF91B4CF),
    Color(0xFF096AB5): Color(0xFF3E92CC),
    Color(0xFF08768C): Color(0xFF23648A),
    Color(0xFF172B43): Color(0xFF0D2D44),
    Color(0xFF435970): Color(0xFF284D68),
    Color(0xFF50647C): Color(0xFF36566D),
  };
  static final sandColors = {
    Color(0xFFD5DFE9): Color(0xFFE5E1DA),
    Color(0xFFE2E8EF): Color(0xFFF2EEE7),
    Color(0xFFD3DEE9): Color(0xFFE8E3DB),
    Color(0xFFCBD7E3): Color(0xFFE2DBD0),
    Color(0xFFDAE4EE): Color(0xFFEDE7DD),
    Color(0xFFAFBFD0): Color(0xFFC5BCAD),
    Color(0xFF096AB5): Color(0xFF8A5D33),
    Color(0xFF08768C): Color(0xFF855C37),
    Color(0xFF172B43): Color(0xFF302F2C),
    Color(0xFF435970): Color(0xFF57534C),
    Color(0xFF50647C): Color(0xFF625D53),
  };
  static final sageColors = {
    Color(0xFFD5DFE9): Color(0xFFE1E5E2),
    Color(0xFFE2E8EF): Color(0xFFEFF2EF),
    Color(0xFFD3DEE9): Color(0xFFE3E9E4),
    Color(0xFFCBD7E3): Color(0xFFDCE4DE),
    Color(0xFFDAE4EE): Color(0xFFE7ECE8),
    Color(0xFFAFBFD0): Color(0xFFB7C5BC),
    Color(0xFF096AB5): Color(0xFF46715B),
    Color(0xFF08768C): Color(0xFF416C58),
    Color(0xFF172B43): Color(0xFF26332E),
    Color(0xFF435970): Color(0xFF4B5E53),
    Color(0xFF50647C): Color(0xFF56675D),
  };
  static final petroleumColors = {
    Color(0xFF0B1220): Color(0xFF20282D),
    Color(0xFF152235): Color(0xFF2B353C),
    Color(0xFF101B2D): Color(0xFF243139),
    Color(0xFF203148): Color(0xFF36434C),
    Color(0xFF33465D): Color(0xFF53656F),
    Color(0xFF38BDF8): Color(0xFF61BAC0),
    Color(0xFF22D3EE): Color(0xFF72C9CB),
    Color(0xFFE8EFF7): Color(0xFFE5EBEF),
    Color(0xFFABBBD0): Color(0xFFB9C9D2),
    Color(0xFF8FA4BC): Color(0xFFA6BAC5),
  };
  static Color resolve(Color light, Color darkColor, {required bool isDark}) {
    final theme = AppAppearance.instance.value;
    if (isDark) {
      final colors = switch (theme) {
        AppVisualTheme.black => blackColors,
        AppVisualTheme.ocean => oceanColors,
        AppVisualTheme.petroleum => petroleumColors,
        AppVisualTheme.sand => sandColors,
        AppVisualTheme.sage => sageColors,
        AppVisualTheme.rose => roseColors,
        AppVisualTheme.ruby => rubyColors,
        _ => const <Color, Color>{},
      };
      return colors[darkColor] ?? darkColor;
    }
    final colors = switch (theme) {
      AppVisualTheme.sand => sandColors,
      AppVisualTheme.slate => slateColors,
      AppVisualTheme.azure => azureColors,
      AppVisualTheme.sage => sageColors,
      AppVisualTheme.rose => roseColors,
      AppVisualTheme.ruby => rubyColors,
      _ => const <Color, Color>{},
    };
    return colors[light] ?? light;
  }

  static Color choose(Color light, Color darkColor) =>
      resolve(light, darkColor, isDark: dark);
  static final blackColors = {
    Color(0xFF0B1220): Color(0xFF090A0C),
    Color(0xFF152235): Color(0xFF17191D),
    Color(0xFF101B2D): Color(0xFF111317),
    Color(0xFF203148): Color(0xFF24272D),
    Color(0xFF33465D): Color(0xFF373C45),
    Color(0xFF38BDF8): Color(0xFF90BFFF),
    Color(0xFF22D3EE): Color(0xFF90BFFF),
    Color(0xFFE8EFF7): Color(0xFFF0F2F5),
    Color(0xFFABBBD0): Color(0xFFB9C0CB),
    Color(0xFF8FA4BC): Color(0xFF9DA7B5),
  };
  static final roseColors = {
    Color(0xFFD5DFE9): Color(0xFFE5E5E9),
    Color(0xFFE2E8EF): Color(0xFFF0F0F3),
    Color(0xFFD3DEE9): Color(0xFFE5E5EB),
    Color(0xFFCBD7E3): Color(0xFFDDDDE4),
    Color(0xFFDAE4EE): Color(0xFFEAEAF0),
    Color(0xFFAFBFD0): Color(0xFFBFC0CA),
    Color(0xFF096AB5): Color(0xFFA85179),
    Color(0xFF08768C): Color(0xFF9C486E),
    Color(0xFF172B43): Color(0xFF30313B),
    Color(0xFF435970): Color(0xFF535564),
    Color(0xFF50647C): Color(0xFF616372),
  };
  static final rubyColors = {
    Color(0xFFD5DFE9): Color(0xFFE3E5E8),
    Color(0xFFE2E8EF): Color(0xFFEFF0F2),
    Color(0xFFD3DEE9): Color(0xFFE3E6EA),
    Color(0xFFCBD7E3): Color(0xFFDADFE4),
    Color(0xFFDAE4EE): Color(0xFFE8EBEF),
    Color(0xFFAFBFD0): Color(0xFFBCC3CC),
    Color(0xFF096AB5): Color(0xFFA83C52),
    Color(0xFF08768C): Color(0xFFA0384D),
    Color(0xFF172B43): Color(0xFF2D333B),
    Color(0xFF435970): Color(0xFF4E5966),
    Color(0xFF50647C): Color(0xFF5C6673),
  };
  static Color get background =>
      choose(const Color(0xFFD5DFE9), const Color(0xFF0B1220));
  static Color get surface =>
      choose(const Color(0xFFE2E8EF), const Color(0xFF152235));
  static Color get field =>
      choose(const Color(0xFFD3DEE9), const Color(0xFF101B2D));
  static Color get header =>
      choose(const Color(0xFFCBD7E3), const Color(0xFF101B2D));
  static Color get raised =>
      choose(const Color(0xFFDAE4EE), const Color(0xFF203148));
  static Color get border =>
      choose(const Color(0xFFAFBFD0), const Color(0xFF33465D));
  static Color get text =>
      choose(const Color(0xFF172B43), const Color(0xFFE8EFF7));
  static Color get secondary =>
      choose(const Color(0xFF435970), const Color(0xFFABBBD0));
  static Color get muted =>
      choose(const Color(0xFF50647C), const Color(0xFF8FA4BC));
  static Color get primary =>
      choose(const Color(0xFF096AB5), const Color(0xFF38BDF8));
  static Color foregroundForPrimary(Color color, {required bool isDark}) =>
      isDark
          ? const Color(0xFF0B1220)
          : (color.computeLuminance() > 0.183
              ? const Color(0xFF0C2434)
              : Colors.white);
  static Color get onPrimary => foregroundForPrimary(primary, isDark: dark);
  static Color get accent =>
      choose(const Color(0xFF08768C), const Color(0xFF22D3EE));
  static Color get success =>
      choose(const Color(0xFF087655), const Color(0xFF34D399));
  static Color get warning =>
      choose(const Color(0xFF955500), const Color(0xFFFBBF24));
  static Color get danger =>
      choose(const Color(0xFFBE3038), const Color(0xFFF87171));
  static Color get subtle => text.withValues(alpha: dark ? 0.08 : 0.06);
}
