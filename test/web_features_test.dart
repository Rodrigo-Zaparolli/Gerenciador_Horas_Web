import 'dart:convert';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_excel_preview_service.dart';
import 'package:gerenciador_horas/data/services/project_file_service.dart';
import 'package:gerenciador_horas/domain/models/timer_session.dart';
import 'package:gerenciador_horas/features/edesk/screens/edesk_webview_browser_screen.dart';

void main() {
  test('Link compartilhado exige protocolo e host válidos', () {
    expect(ProjectFileService.isWebLink('https://example.com/planilha.xlsx'),
        isTrue);
    expect(ProjectFileService.isWebLink('http://localhost:8080'), isTrue);
    for (final path in [
      r'C:\projetos\arquivo.xlsx',
      'javascript:alert(1)',
      'https:',
      'file:///tmp/file'
    ]) {
      expect(ProjectFileService.isWebLink(path), isFalse);
    }
    expect(ProjectFileService.editedReference('', 'https://example.com/old'),
        isNull);
    if (kIsWeb) {
      expect(() => ProjectFileService.editedReference('arquivo.xlsx', null),
          throwsArgumentError);
      expect(ProjectFileService.editedReference(r'C:\old.xlsx', r'C:\old.xlsx'),
          r'C:\old.xlsx');
    }
  });

  test('Cronômetro recuperado conta segmento ativo e exclui pausa', () {
    final start = DateTime.utc(2026, 1, 1, 10);
    final running = TimerSession(
        targetId: '123_1',
        startedAt: start,
        segmentStartedAt: start.add(const Duration(minutes: 30)),
        accumulatedSeconds: 600);
    final restored = TimerSession.fromJson(running.toJson())!;
    expect(
        restored.elapsedSeconds(start.add(const Duration(minutes: 45))), 1500);
    final paused =
        TimerSession.fromJson({...running.toJson(), 'segmentStartedAt': null})!;
    expect(paused.elapsedSeconds(start.add(const Duration(hours: 4))), 600);
    expect(
        TimerSession.fromJson({...running.toJson(), 'accumulatedSeconds': -1}),
        isNull);
    expect(TimerSession.fromJson({...running.toJson(), 'startedAt': 'invalid'}),
        isNull);
  });

  testWidgets('Prévia XLSX selecionada gera PNG sem Firebase ou Python',
      (tester) async {
    final workbook = excel.Excel.createExcel();
    final sheet = workbook['Dados'];
    sheet.cell(excel.CellIndex.indexByString('A1')).value =
        excel.TextCellValue('Cliente');
    sheet.cell(excel.CellIndex.indexByString('B1')).value =
        excel.IntCellValue(123);
    final bytes = Uint8List.fromList(workbook.encode()!);
    final service = ProjectExcelPreviewService();
    final image = await tester.runAsync(() => service.renderBytesAsBase64(
          bytes: bytes,
          rangeReference: "'Dados'!\$A\$1:\$B\$2",
        ));
    expect(base64Decode(image!).take(8).toList(),
        [137, 80, 78, 71, 13, 10, 26, 10]);
    await expectLater(
        service.renderBytesAsBase64(
            bytes: bytes, rangeReference: 'Dados!B2:A1'),
        throwsArgumentError);
    await expectLater(
        service.renderBytesAsBase64(
            bytes: bytes, rangeReference: 'Dados!A1:Z40'),
        throwsArgumentError);
    await expectLater(
        service.renderBytesAsBase64(
            bytes: bytes, rangeReference: 'Ausente!A1:B2'),
        throwsStateError);
    await expectLater(
        service.renderBytesAsBase64(
            bytes: bytes, rangeReference: 'Dados!A0:B2'),
        throwsArgumentError);
  });

  testWidgets('E-Desk no navegador oferece nova aba sem WebView Windows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: EdeskWebViewTestScreen(solicitacao: '123', idTrabalho: '456')));
    expect(find.text('Abrir E-Desk'), findsOneWidget);
    expect(find.text('Solicitação: 123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
