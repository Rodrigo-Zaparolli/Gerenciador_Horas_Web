import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/progresso_projeto_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/grafico_horas_widget.dart';

double parseHours(String text) {
  final parts = text.split(':').map(int.parse).toList();
  return parts[0] + parts[1] / 60;
}

String formatHours(double value) {
  final minutes = (value * 60).round();
  return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

TaskModel task(String id, String hours) => TaskModel(
    subId: id,
    stage: 'Etapa $id',
    status: 'TRAB',
    startDate: DateTime(2026, 10, 9),
    estimatedHours: hours,
    hourType: 'Hs Cobradas');
TimeLog log(String id, String target, String hours) => TimeLog(
    id: id,
    targetId: target,
    projectId: '100',
    date: DateTime(2026, 10, 9),
    startTime: '08:00',
    endTime: '09:00',
    durationFormatted: hours,
    isRegistered: false);
ProjectModel project(List<TaskModel> tasks) => ProjectModel(
    id: '100',
    id2: '',
    client: 'Cliente',
    serviceType: 'Consultoria',
    stage: '',
    task: '',
    status: 'TRAB',
    startDate: DateTime(2026, 10, 9),
    estimatedHours: '17:00',
    leader: '',
    hourType: 'Hs Cobradas',
    subTasks: tasks);

void main() {
  testWidgets(
      'horas do projeto contam logs uma vez e etapas usam suas previsões',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 650,
                height: 260,
                child: ProgressoProjetoWidget(
                    activeProject:
                        project([task('2', '01:00'), task('3', '02:00')]),
                    timeLogs: [
                      log('a', '100_2', '01:00'),
                      log('b', '100_3', '01:30'),
                      log('c', '100', '06:00')
                    ],
                    parseTimeToHours: parseHours,
                    formatHours: formatHours,
                    formatDateShort: (date) => '09/10/2026')))));
    expect(tester.takeException(), isNull);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))
        .toList();
    expect(bars.map((bar) => bar.value), [0.5, 1.0, 0.75]);
    expect(find.text('08:30'), findsNWidgets(2));
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'etapa com excesso não gera saldo negativo; largura móvel não corta controles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                height: 260,
                child: ProgressoProjetoWidget(
                    activeProject:
                        project([task('2', '01:00'), task('3', '00:00')]),
                    timeLogs: [
                      log('a', '100_2', '02:00'),
                      log('b', '100_3', '00:30')
                    ],
                    parseTimeToHours: parseHours,
                    formatHours: formatHours,
                    formatDateShort: (date) => '09/10/2026')))));
    expect(tester.takeException(), isNull);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))
        .toList();
    expect(bars[1].value, 1);
    expect(bars[2].value, 0);
    expect(find.text('00:00'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gráfico usa escala dos dados e mantém clique em dias sem horas',
      (tester) async {
    DateTime? selected;
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final previous = DateTime(first.year, first.month, first.day - 8);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 350,
                height: 260,
                child: GraficoHorasWidget(
                    monthlyWorked: 12,
                    points: [
                      DailyHoursPoint(label: 'Hoje', hours: 0, date: first),
                      DailyHoursPoint(
                          label: 'Anterior', hours: 12, date: previous)
                    ],
                    formatHours: formatHours,
                    onDayTap: (date) => selected = date)))));
    expect(tester.takeException(), isNull);
    expect(find.text('12:00'), findsNWidgets(3));
    await tester.tap(find.text('Hoje'));
    expect(selected, first);
    await tester.pumpWidget(const SizedBox());
  });
}
