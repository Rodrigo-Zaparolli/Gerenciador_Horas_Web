import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_excel_preview_service.dart';
import 'package:gerenciador_horas/data/services/native_local_files_service.dart';

void main() {
  test(
      'Native preview uses the endpoint response and preserves range and reference',
      () async {
    final calls = <String>[];
    final service = ProjectExcelPreviewService(
        nativeRequest: (action, {reference, name, range}) async {
      calls.add(action);
      expect(reference, 'linked-workbook');
      expect(range, "'Dados'!A1:L8");
      return {'renderer': 'excel', 'imagemBase64': 'native-image'};
    });
    expect(
        await service.renderRangeAsBase64(
            fileReference: 'linked-workbook',
            rangeReference: "'Dados'!A1:L8",
            preserveLayout: true),
        'native-image');
    expect(calls, ['preview']);
  });

  test(
      'Empty preview reports capture failure without asking to update a ready package',
      () async {
    final service = ProjectExcelPreviewService(
        nativeRequest: (action, {reference, name, range}) async =>
            {'renderer': 'excel', 'imagemBase64': ''});
    await expectLater(
        service.renderRangeAsBase64(
            fileReference: 'linked-workbook',
            rangeReference: 'A1:L8',
            preserveLayout: true),
        throwsA(isA<NativeFilesException>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('não gerou a imagem'), isNot(contains('Atualize'))))));
  });

  test('Canceling the native selection does not insert a preview', () async {
    final service = ProjectExcelPreviewService(
        nativeRequest: (action, {reference, name, range}) async =>
            {'cancelled': true});
    await expectLater(
        service.renderRangeAsBase64(
            fileReference: 'linked-workbook',
            rangeReference: 'A1:L8',
            preserveLayout: true),
        throwsA(isA<NativeFilesException>().having(
            (e) => e.message, 'message', contains('Selecione a planilha'))));
  });
}
