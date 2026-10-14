import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_pdf_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TimeLog log(String id, DateTime date,
          {bool registered = true,
          String type = 'Hs Cobradas',
          String project = '2256824'}) =>
      TimeLog(
          id: id,
          targetId: '${project}_4',
          date: date,
          startTime: '08:00',
          endTime: '09:30',
          durationFormatted: '01:30',
          durationMinutes: 90,
          isRegistered: registered,
          projectId: project,
          projectName: '$project - Cliente de exemplo',
          taskName: 'Treinamento Catálogo',
          typeHs: type,
          description:
              'Orientação ao cliente e revisão das configurações.\nValidação das atividades realizadas.');
  test('sorts actual dates across months and counts only registered hours', () {
    final data = TaskReportData([
      log('a', DateTime(2026, 9, 30)),
      log('b', DateTime(2026, 10, 1), type: 'Hs Internas'),
      log('c', DateTime(2026, 10, 2), registered: false),
      log('d', DateTime(2026, 10, 1), type: 'Outro', project: '2265173')
    ], (log) => log.durationMinutes);
    expect(data.byDate.keys.first, DateTime(2026, 10, 1));
    expect(data.logs.length, 3);
    expect(data.total, 270);
    expect(data.byType, {'Cobradas': 90, 'Internas': 90, 'Outras': 90});
    expect(data.projects.length, 2);
    expect(reportHours(data.total), '04:30');
  });
  test('large report generates multiple pages and a reviewable sample',
      () async {
    final data = TaskReportData(
        List.generate(120, (i) => log('$i', DateTime(2026, 10, 10))),
        (log) => log.durationMinutes);
    final pdf = await buildTaskPdfReport(
        data: data,
        period: '01/10/2026 até 10/10/2026',
        responsible: 'Rodrigo Zaparolli',
        generatedAt: DateTime(2026, 10, 11));
    final bytes = await pdf.save();
    expect(bytes.take(4).toList(), [37, 80, 68, 70]);
    expect(pdf.document.pdfPageList.pages.length, greaterThan(2));
    final example = await buildTaskPdfReport(
        data: TaskReportData([
          log('1', DateTime(2026, 10, 10)),
          log('2', DateTime(2026, 10, 10), type: 'Hs Internas'),
          log('3', DateTime(2026, 10, 9), project: '2265173')
        ], (log) => log.durationMinutes),
        period: '09/10/2026 até 10/10/2026',
        responsible: 'Rodrigo Zaparolli',
        generatedAt: DateTime(2026, 10, 11));
    await Directory('build/pdf-preview').create(recursive: true);
    await File('build/pdf-preview/relatorio-atividades-exemplo.pdf')
        .writeAsBytes(await example.save());
    await File('build/pdf-preview/relatorio-atividades-multipaginas.pdf')
        .writeAsBytes(bytes);
  });
  test('long descriptions keep all text and paginate without overflowing',
      () async {
    final description = List.filled(
            150, 'Descrição das atividades e configuração do catálogo.\n')
        .join();
    expect(reportDescriptionChunks(description).join(), description);
    final item = log('long', DateTime(2026, 10, 10))..description = description;
    final pdf = await buildTaskPdfReport(
        data: TaskReportData([item], (log) => log.durationMinutes),
        period: '10/10/2026',
        responsible: 'Rodrigo',
        generatedAt: DateTime(2026, 10, 11));
    expect((await pdf.save()).length, greaterThan(1000));
    expect(pdf.document.pdfPageList.pages.length, greaterThan(1));
  });
}
