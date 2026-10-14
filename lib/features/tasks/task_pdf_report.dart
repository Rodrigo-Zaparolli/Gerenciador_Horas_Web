import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

String reportHours(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
String reportDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

// Keep each table row short enough to fit a page without dropping any text.
List<String> reportDescriptionChunks(String value) {
  final chunks = <String>[];
  var remaining = value;
  while (remaining.isNotEmpty) {
    var end = remaining.length > 800 ? 800 : remaining.length;
    var lineCount = 0;
    for (var i = 0; i < end; i++) {
      if (remaining[i] == '\n' && ++lineCount == 16) {
        end = i + 1;
        break;
      }
    }
    if (end < remaining.length) {
      final boundary = remaining.lastIndexOf(' ', end - 1);
      if (boundary > end ~/ 2) end = boundary + 1;
    }
    chunks.add(remaining.substring(0, end));
    remaining = remaining.substring(end);
  }
  return chunks.isEmpty ? [''] : chunks;
}

class TaskReportData {
  TaskReportData(List<TimeLog> source, this.minutes) {
    logs = source.where((log) => log.isRegistered).toList()
      ..sort((a, b) {
        final date = DateTime(b.date.year, b.date.month, b.date.day)
            .compareTo(DateTime(a.date.year, a.date.month, a.date.day));
        return date != 0 ? date : a.startTime.compareTo(b.startTime);
      });
    for (final log in logs) {
      final date = DateTime(log.date.year, log.date.month, log.date.day);
      byDate.putIfAbsent(date, () => []).add(log);
      total += minutes(log);
      final type = (log.typeHs ?? '').toLowerCase();
      final category = type.contains('cobrad')
          ? 'Cobradas'
          : type.contains('intern')
              ? 'Internas'
              : 'Outras';
      byType.update(category, (value) => value + minutes(log),
          ifAbsent: () => minutes(log));
      projects.add(log.projectId?.trim().isNotEmpty == true
          ? log.projectId!
          : log.targetId.split('_').first);
    }
  }
  final int Function(TimeLog) minutes;
  late final List<TimeLog> logs;
  final byDate = <DateTime, List<TimeLog>>{};
  final byType = <String, int>{};
  final projects = <String>{};
  int total = 0;
}

Future<pw.Document> buildTaskPdfReport(
    {required TaskReportData data,
    required String period,
    required String responsible,
    required DateTime generatedAt}) async {
  const navy = PdfColor.fromInt(0xFF172B43);
  const blue = PdfColor.fromInt(0xFF096AB5);
  const muted = PdfColor.fromInt(0xFF50647C);
  const border = PdfColor.fromInt(0xFFD5DFE9);
  const surface = PdfColor.fromInt(0xFFF2F5F8);
  final font =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final boldFont =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
      title: 'Relatório de atividades',
      author: responsible,
      creator: 'Gerenciador de Horas');
  pw.Text text(String value,
          {double size = 9, PdfColor color = navy, bool bold = false}) =>
      pw.Text(value,
          style: pw.TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));
  pw.Widget cell(String value, {bool bold = false, PdfColor color = navy}) =>
      pw.Padding(
          padding: const pw.EdgeInsets.all(7),
          child: text(value, size: 8.5, color: color, bold: bold));
  pw.Widget metric(String label, String value) => pw.Expanded(
      child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: surface,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: border)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text(label, size: 8, color: muted),
                pw.SizedBox(height: 6),
                text(value, size: 20, color: blue, bold: true)
              ])));
  pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
      maxPages: 1000,
      header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: border))),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                text('GERENCIADOR DE HORAS', size: 9, bold: true),
                text('Relatório de atividades', size: 9, color: muted)
              ])),
      footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: border))),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                text('Emitido em ${reportDate(generatedAt)}',
                    size: 8, color: muted),
                text('Página ${context.pageNumber} de ${context.pagesCount}',
                    size: 8, color: muted)
              ])),
      build: (context) => [
            pw.SizedBox(height: 14),
            text('Relatório de atividades', size: 23, bold: true),
            pw.SizedBox(height: 7),
            text(period, size: 11, color: blue, bold: true),
            pw.SizedBox(height: 6),
            text('Responsável: $responsible', color: muted),
            pw.SizedBox(height: 5),
            text('Somente apontamentos registrados', size: 8, color: muted),
            pw.SizedBox(height: 18),
            pw.Row(children: [
              metric('HORAS NO PERÍODO', reportHours(data.total)),
              pw.SizedBox(width: 8),
              metric('APONTAMENTOS', '${data.logs.length}'),
              pw.SizedBox(width: 8),
              metric('PROJETOS', '${data.projects.length}')
            ]),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              for (final type in ['Cobradas', 'Internas', 'Outras']) ...[
                text('$type: ${reportHours(data.byType[type] ?? 0)}',
                    size: 9, color: muted),
                pw.SizedBox(width: 20)
              ]
            ]),
            pw.SizedBox(height: 18),
            for (final entry in data.byDate.entries) ...[
              pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: pw.BoxDecoration(
                      color: surface,
                      borderRadius: pw.BorderRadius.circular(5)),
                  child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        text(reportDate(entry.key), size: 10, bold: true),
                        text(
                            'Total do dia: ${reportHours(entry.value.fold(0, (sum, log) => sum + data.minutes(log)))}',
                            color: blue,
                            bold: true)
                      ])),
              pw.SizedBox(height: 6),
              pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.1),
                    1: pw.FlexColumnWidth(3.2),
                    2: pw.FlexColumnWidth(1.2),
                    3: pw.FlexColumnWidth(1.35),
                    4: pw.FlexColumnWidth(1)
                  },
                  border: const pw.TableBorder(
                      horizontalInside:
                          pw.BorderSide(color: border, width: 0.4)),
                  children: [
                    pw.TableRow(
                        repeat: true,
                        decoration: const pw.BoxDecoration(color: navy),
                        children: [
                          for (final label in [
                            'PROJETO / CLIENTE',
                            'TAREFA / DESCRIÇÃO',
                            'TIPO',
                            'HORÁRIO',
                            'HORAS'
                          ])
                            cell(label, bold: true, color: PdfColors.white)
                        ]),
                    for (var i = 0; i < entry.value.length; i++)
                      for (final part in reportDescriptionChunks([
                        (entry.value[i].taskName ?? entry.value[i].targetId)
                            .trim(),
                        if ((entry.value[i].description ?? '')
                            .trim()
                            .isNotEmpty)
                          entry.value[i].description!.trim()
                      ].join('\n\n'))
                          .asMap()
                          .entries)
                        pw.TableRow(
                            decoration: pw.BoxDecoration(
                                color: i.isOdd ? surface : PdfColors.white),
                            children: [
                              cell(
                                  part.key == 0
                                      ? (entry.value[i].projectName ??
                                              entry.value[i].targetId)
                                          .trim()
                                      : '',
                                  bold: true),
                              cell(part.value),
                              cell(part.key == 0
                                  ? entry.value[i].typeHs ?? ''
                                  : ''),
                              cell(part.key == 0
                                  ? '${entry.value[i].startTime}\n${entry.value[i].endTime}'
                                  : ''),
                              cell(
                                  part.key == 0
                                      ? reportHours(
                                          data.minutes(entry.value[i]))
                                      : '',
                                  color: blue,
                                  bold: true),
                            ])
                  ]),
              pw.SizedBox(height: 14),
            ],
          ]));
  return pdf;
}
