import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_preference.dart';

/// One application-wide appearance, independent of business data and login.
enum AppVisualTheme {
  light('light', 'Claro', Icons.light_mode_outlined),
  dark('dark', 'Escuro', Icons.dark_mode_outlined),
  sand('sand', 'Areia', Icons.wb_sunny_outlined),
  sage('sage', 'Sálvia', Icons.spa_outlined),
  petroleum('petroleum', 'Azul petróleo', Icons.nights_stay_outlined),
  rose('rose', 'Rosa suave', Icons.local_florist_outlined),
  ruby('ruby', 'Vermelho rubi', Icons.diamond_outlined),
  black('black', 'Black', Icons.dark_mode_outlined),
  slate('slate', 'Azul ardósia', Icons.landscape_outlined),
  ocean('ocean', 'Azul oceano', Icons.water_outlined),
  azure('azure', 'Azul celeste', Icons.cloud_outlined);

  const AppVisualTheme(this.preference, this.label, this.icon);
  final String preference;
  final String label;
  final IconData icon;
  ThemeMode get mode => switch (this) {
        dark || petroleum || black || ocean => ThemeMode.dark,
        _ => ThemeMode.light,
      };
}

class AppAppearance extends ValueNotifier<AppVisualTheme> {
  AppAppearance({AppVisualTheme initialMode = AppVisualTheme.light})
      : super(initialMode);
  static final instance = AppAppearance();
  Future<void> _pendingWrite = Future.value();

  bool get isDark => value.mode == ThemeMode.dark;

  Future<void> restore() async {
    final saved = await readThemePreference();
    if (saved == 'soft') {
      select(AppVisualTheme.light);
      await _pendingWrite;
      return;
    }
    for (final theme in AppVisualTheme.values) {
      if (saved == theme.preference) {
        value = theme;
        break;
      }
    }
  }

  void select(AppVisualTheme theme) {
    value = theme;
    final preference = theme.preference;
    _pendingWrite = _pendingWrite.then((_) => writeThemePreference(preference));
    unawaited(_pendingWrite);
  }

  /// Registers the widget for changes without replacing its state or route.
  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
  }
}

class AppearanceScope extends InheritedNotifier<AppAppearance> {
  const AppearanceScope(
      {super.key, required AppAppearance controller, required super.child})
      : super(notifier: controller);
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppVisualTheme>(
        valueListenable: AppAppearance.instance,
        builder: (context, mode, child) {
          return PopupMenuButton<AppVisualTheme>(
            key: const ValueKey('appearance-toggle'),
            tooltip: 'Escolher tema',
            onSelected: AppAppearance.instance.select,
            itemBuilder: (context) => [
              for (final theme in AppVisualTheme.values)
                PopupMenuItem(
                  value: theme,
                  child: Row(children: [
                    _ThemeSymbol(theme: theme),
                    const SizedBox(width: 12),
                    Expanded(child: Text(theme.label)),
                    if (mode == theme)
                      Icon(Icons.check_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                  ]),
                ),
            ],
            icon: _ThemeSymbol(theme: mode),
          );
        },
      );
}

/// Vector symbols remain visible even when a browser caches an old icon font.
class _ThemeSymbol extends StatelessWidget {
  const _ThemeSymbol({required this.theme});
  final AppVisualTheme theme;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 21,
        child: CustomPaint(
          painter:
              _ThemeSymbolPainter(theme, Theme.of(context).colorScheme.primary),
        ),
      );
}

class _ThemeSymbolPainter extends CustomPainter {
  const _ThemeSymbolPainter(this.theme, this.color);
  final AppVisualTheme theme;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (theme) {
      case AppVisualTheme.slate:
        canvas.drawPath(
            Path()
              ..moveTo(2, 20)
              ..lineTo(8, 7)
              ..lineTo(13, 14)
              ..lineTo(17, 9)
              ..lineTo(22, 20)
              ..close(),
            pen);
      case AppVisualTheme.ocean:
        canvas.drawPath(
            Path()
              ..moveTo(2, 16)
              ..cubicTo(7, 16, 7, 4, 14, 4)
              ..cubicTo(23, 4, 20, 14, 14, 12)
              ..cubicTo(14, 18, 20, 20, 22, 20)
              ..lineTo(2, 20),
            pen);
      case AppVisualTheme.azure:
        canvas.drawPath(
            Path()
              ..moveTo(6, 19)
              ..cubicTo(0, 19, 0, 10, 6, 10)
              ..cubicTo(7, 1, 19, 1, 19, 11)
              ..cubicTo(25, 11, 25, 19, 19, 19)
              ..close(),
            pen);
      case AppVisualTheme.black:
        canvas.drawCircle(const Offset(12, 12), 9, pen);
        canvas.drawCircle(
            const Offset(12, 12),
            4,
            Paint()
              ..color = color
              ..style = PaintingStyle.fill);
      case AppVisualTheme.light:
        canvas.drawCircle(const Offset(12, 12), 4, pen);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          canvas.drawLine(
              Offset(12 + 7 * math.cos(angle), 12 + 7 * math.sin(angle)),
              Offset(12 + 10 * math.cos(angle), 12 + 10 * math.sin(angle)),
              pen);
        }
      case AppVisualTheme.dark:
        canvas.drawPath(
            Path()
              ..moveTo(17, 3)
              ..cubicTo(2, 0, 0, 19, 12, 21)
              ..cubicTo(18, 22, 23, 17, 22, 12)
              ..cubicTo(14, 16, 9, 8, 17, 3)
              ..close(),
            pen);
      case AppVisualTheme.sand:
        canvas.drawCircle(const Offset(17, 6), 3, pen);
        canvas.drawPath(
            Path()
              ..moveTo(2, 17)
              ..quadraticBezierTo(8, 7, 14, 17)
              ..quadraticBezierTo(18, 12, 22, 17)
              ..moveTo(2, 21)
              ..lineTo(22, 21),
            pen);
      case AppVisualTheme.sage:
        canvas.drawPath(
            Path()
              ..moveTo(5, 20)
              ..cubicTo(0, 7, 14, 3, 21, 3)
              ..cubicTo(21, 14, 17, 22, 5, 20)
              ..close()
              ..moveTo(3, 22)
              ..lineTo(16, 9),
            pen);
      case AppVisualTheme.petroleum:
        for (final y in [6.0, 12.0, 18.0]) {
          canvas.drawPath(
              Path()
                ..moveTo(2, y)
                ..cubicTo(8, y - 5, 14, y + 5, 22, y),
              pen);
        }
      case AppVisualTheme.rose:
        for (var i = 0; i < 5; i++) {
          final angle = i * math.pi * 2 / 5 - math.pi / 2;
          canvas.drawCircle(
              Offset(12 + 6 * math.cos(angle), 12 + 6 * math.sin(angle)),
              4,
              pen);
        }
        canvas.drawCircle(const Offset(12, 12), 2, pen);
      case AppVisualTheme.ruby:
        canvas.drawPath(
            Path()
              ..moveTo(3, 8)
              ..lineTo(7, 3)
              ..lineTo(17, 3)
              ..lineTo(21, 8)
              ..lineTo(12, 22)
              ..close()
              ..moveTo(3, 8)
              ..lineTo(21, 8)
              ..moveTo(7, 3)
              ..lineTo(9, 8)
              ..lineTo(12, 22)
              ..lineTo(15, 8)
              ..lineTo(17, 3),
            pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ThemeSymbolPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.color != color;
}
