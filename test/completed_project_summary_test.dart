import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/completed_projects/completed_project_summary.dart';

void main() {
  DateTime? parse(dynamic value) => value is DateTime ? value : DateTime.tryParse('$value');
  test('completion uses latest work date regardless of task order or archive date', () {
    final project = <String, dynamic>{'finalizedAt': '2026-10-10', 'subTasks': [
      {'planEnd': '2026-09-10'}, {'planEnd': null}, {'planEnd': '2026-05-26'}]};
    expect(completedProjectEndDate(project, parse), DateTime(2026,9,10));
    expect(completedProjectEndDate({'finalizedAt':'2026-10-10'}, parse), DateTime(2026,10,10));
    expect(completedProjectEndDate({}, parse), isNull);
  });
  TimeLog log(String id, String target, int minutes) => TimeLog(id:id, targetId:target,
      date:DateTime(2026,9,10), startTime:'08:00', endTime:'09:00',
      durationFormatted:'', durationMinutes:minutes, isRegistered:false);
  final summary = CompletedHoursSummary.calculate(projectId:'2256824', estimatedHours:'03:00',
      tasks:[{'subId':'8','stage':'Implantação','estimatedHours':'02:00'},
             {'subId':'4','stage':'Contato inicial','estimatedHours':'01:00'}],
      logs:[log('a','2256824_4',30),log('b','2256824_8',150),log('c','2256824',30),log('d','2256824_99',15)],
      parseMinutes:(value) {final parts=value.split(':'); return int.parse(parts[0])*60+int.parse(parts[1]);},
      logMinutes:(log)=>log.durationMinutes);
  test('totals include unmatched logs once, match stage IDs, and preserve overrun', () {
    expect(summary.total.used,225);
    expect(summary.total.balance,-45);
    expect(summary.stages.first.used,150);
    expect(summary.stages[1].used,30);
    expect(summary.stages.last.name,'Sem etapa vinculada');
    expect(summary.stages.last.used,45);
    expect(summary.stages.fold(0,(sum,row)=>sum+row.used),summary.total.used);
    expect(completedHoursText(summary.total.balance),'-00:45');
  });
  for (final theme in AppVisualTheme.values) {
    for (final width in [360.0,940.0]) {
      testWidgets('summary fits $theme at $width including all stages', (tester) async {
        AppAppearance.instance.value=theme;
        addTearDown(()=>AppAppearance.instance.value=AppVisualTheme.light);
        tester.view.physicalSize=Size(width,900);
        tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(theme:theme.mode==ThemeMode.dark?AppTheme.dark:AppTheme.light,
            home:Scaffold(body:SingleChildScrollView(child:CompletedProjectSummaryCard(summary:summary)))));
        expect(find.text('Resumo de horas do projeto'),findsOneWidget);
        expect(find.text('Sem etapa vinculada'),findsOneWidget);
        expect(find.text('Excedente: 00:45'),findsOneWidget);
        expect(tester.takeException(),isNull);
      });
    }
  }
}
