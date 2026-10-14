import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/metrics/monthly_performance.dart';

TimeLog log(DateTime date, int minutes, String type) => TimeLog(
    id: '$date$type',
    targetId: '123_4',
    date: date,
    startTime: '08:00',
    endTime: '17:00',
    durationFormatted: '',
    durationMinutes: minutes,
    typeHs: type,
    isRegistered: true);

void main() {
  test('daily labels identify weekends using the displayed month and year', () {
    expect(monthlyDayLabel(DateTime(2026, 10, 3)), '03\nSáb');
    expect(monthlyDayLabel(DateTime(2026, 10, 4)), '04\nDom');
    expect(monthlyDayLabel(DateTime(2026, 10, 5)), '05');
    expect(monthlyDayLabel(DateTime(2026, 11, 1)), '01\nDom');
    expect(monthlyDayLabel(DateTime(2027, 10, 3)), '03\nDom');
  });
  test('legacy charged labels match metrics and never include noncharged hours',
      () {
    final date = DateTime(2026, 10, 1);
    final data = MonthlyPerformanceData(date, [
      log(date, 60, 'HORAS COBRADAS'),
      log(date, 30, 'Cobradas'),
      log(date, 120, 'Hs Não cobradas')
    ]);
    expect(data.billed, 90);
    expect(data.worked, 210);
  });
  test('daily totals preserve actual duration, categories and year isolation',
      () {
    final data = MonthlyPerformanceData(DateTime(2026, 10), [
      log(DateTime(2026, 10, 1), 90, 'Hs Cobradas'),
      log(DateTime(2026, 10, 1), 30, 'Hs Internas'),
      log(DateTime(2026, 10, 2), 60, 'Hs Investimento'),
      log(DateTime(2025, 10, 1), 1000, 'Hs Cobradas'),
    ]);
    expect(data.billed, 90);
    expect(data.worked, 180);
    expect(data.charged.first, 90);
    expect(data.other.first, 30);
    expect(data.activeDays, 2);
    expect(data.dailyAverage, 90);
  });
  test('empty leap-year month has correct day count and safe averages', () {
    final data = MonthlyPerformanceData(DateTime(2024, 2), []);
    expect(data.charged.length, 29);
    expect(data.dailyAverage, 0);
  });
  testWidgets(
      'annual month selection updates daily totals without growing the card',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
              child: MonthlyPerformance(
            year: now.year,
            goals: List.filled(12, 600),
            chargedColor: Colors.blue,
            otherColor: Colors.grey,
            logs: [log(DateTime(now.year, 1, 1), 90, 'Hs Cobradas')],
          )),
        )));
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(MonthlyPerformance)).height;
    await tester.tap(find.byKey(const ValueKey('annual-month-1')));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro ${now.year}'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.data == '01:30' &&
            widget.style?.fontSize == 23),
        findsNWidgets(2));
    expect(tester.getSize(find.byType(MonthlyPerformance)).height, height);
    expect(tester.takeException(), isNull);
  });
  for (final theme in AppVisualTheme.values) {
    for (final width in [360.0, 1440.0]) {
      testWidgets('monthly performance fits $theme at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        addTearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
        final now = DateTime.now();
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.mode,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: MonthlyPerformance(
                            year: now.year,
                            goals: List.filled(12, 600),
                            chargedColor: ThemeData(
                                    brightness: theme.mode == ThemeMode.dark
                                        ? Brightness.dark
                                        : Brightness.light)
                                .colorScheme
                                .primary,
                            otherColor: Colors.grey,
                            logs: [
                              log(DateTime(now.year, now.month, 1), 90,
                                  'Hs Cobradas')
                            ]))))));
        await tester.pumpAndSettle();
        expect(find.text('Desempenho mensal'), findsOneWidget);
        expect(find.text('Meta do mês'), findsOneWidget);
        expect(find.text('Comparativo mensal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
