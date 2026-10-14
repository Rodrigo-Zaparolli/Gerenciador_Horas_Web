import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/deadline_alert.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/dashboard_alerts_modal.dart';
import 'dashboard_cards_test.dart' as fixture;

void main() {
  final today = DateTime(2026, 10, 10, 23, 59);
  test('prazos usam a regra existente: atrasos, hoje e próximos cinco dias',
      () {
    final tasks = [
      fixture.task('late', '01:00')..planEnd = DateTime(2026, 10, 8),
      fixture.task('today', '01:00')..planEnd = DateTime(2026, 10, 10),
      fixture.task('five', '01:00')..planEnd = DateTime(2026, 10, 15),
      fixture.task('six', '01:00')..planEnd = DateTime(2026, 10, 16),
      fixture.task('done', '01:00')..status = 'TRAB_FIM',
    ];
    final alerts = DeadlineAlert.collect([fixture.project(tasks)], today);
    expect(alerts.map((row) => row.id2), ['late', 'today', 'five']);
    expect(alerts.map((row) => row.differenceDays), [-2, 0, 5]);
    final done = fixture.project([])..status = 'TRAB_FIM';
    expect(DeadlineAlert.collect([done], today), isEmpty);
  });

  for (final size in [const Size(1200, 800), const Size(320, 568)]) {
    for (final theme in AppVisualTheme.values) {
      testWidgets(
          'popup unifica alertas, rola e retorna ações em $size / $theme',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        addTearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
        final project = fixture.project([fixture.task('2', '08:00')]);
        final deadlines = DeadlineAlert.collect([project], today);
        final updates = [
          PendingProjectUpdate(
              project,
              ProjectCommentUpdate(
                  'sent', DateTime(2026, 9, 26), 'Comentário enviado'),
              today)
        ];
        String? result;
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.mode,
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await DashboardAlertsModal.show(
                              context, deadlines, updates);
                        },
                        child: const Text('Abrir'))))));
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Central de alertas'), findsOneWidget);
        expect(find.text('2 pendências precisam de atenção'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Comentar'));
        await tester.tap(find.text('Comentar'));
        await tester.pumpAndSettle();
        expect(result, 'comment:100');
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Ver na central'));
        await tester.tap(find.text('Ver na central'));
        await tester.pumpAndSettle();
        expect(result, 'alerts');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
