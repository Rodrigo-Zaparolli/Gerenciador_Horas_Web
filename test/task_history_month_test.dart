import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_history_month.dart';
import 'package:gerenciador_horas/features/tasks/task_history_month_panel.dart';

TimeLog entry(DateTime date, int minutes, {String type = 'Hs Cobradas'}) => TimeLog(
  id: '$date', targetId: '123_4', date: date, startTime: '08:00', endTime: '09:00',
  durationFormatted: '', durationMinutes: minutes, typeHs: type,
  projectName: 'Cliente de exemplo', taskName: 'Implantação', isRegistered: true);

void main() {
  test('boundary weeks allocate each log to its actual month and year', () {
    final logs = [entry(DateTime(2026, 9, 28), 100), entry(DateTime(2026, 10, 1), 61),
      entry(DateTime(2026, 10, 31), 90, type: 'Hs Não cobradas'),
      entry(DateTime(2026, 11, 1), 200), entry(DateTime(2026, 12, 31), 300),
      entry(DateTime(2027, 1, 1), 400)];
    final tree = taskHistoryTree(logs);
    expect(tree[2026]![9]!.values.expand((logs) => logs).single.date.month, 9);
    expect(tree[2026]![10]!.values.expand((logs) => logs).length, 2);
    expect(tree[2027]![1]!.values.expand((logs) => logs).single.date.year, 2027);
    expect(tree.values.expand((months) => months.values)
      .expand((weeks) => weeks.values).expand((logs) => logs).length, logs.length);
    final october = TaskHistoryMonth(2026, 10, logs);
    expect(october.minutes, 151);
    expect(october.chargedMinutes, 61);
    expect(october.weeks.first.label, '01 a 04 de outubro');
    expect(october.weeks.last.label, '26 a 31 de outubro');
    expect(october.weeks.fold<int>(0, (sum, week) => sum + week.minutes), 151);
  });
  test('every day appears exactly once, including leap years and empty months', () {
    for (final year in [2024, 2025, 2026, 2027]) {
      for (var month = 1; month <= 12; month++) {
        final data = TaskHistoryMonth(year, month, []);
        final days = data.weeks.expand((week) => week.days).toList();
        expect(days.length, DateTime(year, month + 1, 0).day);
        expect(days.map((day) => day.day).toSet().length, days.length);
        expect(days.every((day) => day.month == month && day.year == year), true);
        expect(days.first.day, 1);
        expect(days.last.day, data.dayCount);
        expect(data.minutes, 0);
      }
    }
  });

  for (final theme in [AppVisualTheme.light, AppVisualTheme.black]) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('monthly weeks and actions fit $theme at $width', (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        addTearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
        DateTime? selected;
        TimeLog? edited;
        final log = entry(DateTime(2026, 10, 1), 60);
        await tester.pumpWidget(MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark,
          themeMode: theme.mode, home: Scaffold(body: TaskHistoryMonthPanel(
            data: TaskHistoryMonth(2026, 10, [log, entry(DateTime(2026, 9, 30), 999)]),
            onSelectDay: (day) => selected = day, onEdit: (log) => edited = log))));
        await tester.pumpAndSettle();
        final firstWeek = find.text('01 a 04 de outubro');
        await tester.ensureVisible(firstWeek);
        // The current week can open initially; explicitly open the first week if necessary.
        if (find.byTooltip('Editar apontamento').evaluate().isEmpty) {
          await tester.tap(firstWeek);
          await tester.pumpAndSettle();
        }
        final edit = find.byTooltip('Editar apontamento');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        expect(edited, same(log));
        final empty = find.byKey(const ValueKey('history-day-2026-10-3'));
        await tester.ensureVisible(empty);
        await tester.tap(find.descendant(of: empty, matching: find.byType(ListTile)).first);
        expect(selected, DateTime(2026, 10, 3));
        expect(find.byKey(const ValueKey('history-day-2026-9-30')), findsNothing);
        expect(tester.takeException(), isNull);
        final lastWeek = find.text('26 a 31 de outubro');
        await tester.scrollUntilVisible(lastWeek, 350, scrollable: find.byType(Scrollable).first);
        await tester.tap(lastWeek);
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('history-day-2026-10-31'));
        await tester.scrollUntilVisible(last, 350, scrollable: find.byType(Scrollable).first);
        expect(last, findsOneWidget);
        expect(find.byKey(const ValueKey('history-day-2026-11-1')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
