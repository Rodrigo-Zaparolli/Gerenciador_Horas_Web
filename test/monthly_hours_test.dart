import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/monthly_hours.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/grafico_horas_widget.dart';

TimeLog log(String type, DateTime date, String hours) => TimeLog(
    id: 'test',
    targetId: 'any-project',
    date: date,
    startTime: '08:00',
    endTime: '09:00',
    durationFormatted: hours,
    isRegistered: false,
    typeHs: type);
void main() {
  test(
      'Worked month includes all categories and excludes other months and years',
      () {
    final now = DateTime(2026, 10, 9);
    expect(
        MonthlyHours.workedInMonth(now, [
          log('Hs Cobradas', now, '36:20'),
          log('Hs Internas', DateTime(2026, 10, 1), '09:00'),
          log('Outra categoria', DateTime(2026, 10, 31), '05:00'),
          log('Hs Investimento', now, '07:00'),
          log('Hs Cobradas', DateTime(2026, 9, 30), '10:00'),
          log('Hs Cobradas', DateTime(2026, 11, 1), '10:00'),
          log('Hs Cobradas', DateTime(2025, 10, 9), '10:00'),
        ]),
        closeTo(57 + 20 / 60, .00001));
    expect(MonthlyHours.workedInMonth(now, []), 0);
  });

  test('Monthly totals exclude other categories, months and years', () {
    final now = DateTime(2026, 10, 9);
    final totals = MonthlyHours.calculate(now, [
      log('Hs Cobradas', now, '36:20'),
      log('Hs Internas', now, '09:00'),
      log('Hs Não cobradas', now, '05:00'),
      log('Hs Investimento', now, '07:00'),
      log('Hs Cobradas', DateTime(2026, 9, 30), '10:00'),
      log('Hs Cobradas', DateTime(2025, 10, 9), '10:00'),
    ], {
      '10': '140:00'
    }, {
      'horasDia': '08:00'
    });
    expect(totals.charged, closeTo(36 + 20 / 60, .00001));
    expect(totals.planned, 176);
    expect(totals.remaining, closeTo(103 + 40 / 60, .00001));
    expect(totals.progress, closeTo((36 + 20 / 60) / 140, .00001));
    final surpassed = MonthlyHours(now, 176, 140, 150);
    expect(surpassed.remaining, 0);
    expect(surpassed.progress, 1);
    expect(MonthlyHours(now, 176, 0, 20).progress, 0);
  });
  for (final width in [320.0, 550.0]) {
    testWidgets('Monthly chart fits compact height at width $width',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: width,
                  height: 260,
                  child: GraficoHorasWidget(
                      points: const [],
                      formatHours: (hours) => '${hours.floor()}:00',
                      monthly:
                          MonthlyHours(DateTime(2026, 10), 176, 140, 36))))));
      expect(find.text('Meta cobrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
