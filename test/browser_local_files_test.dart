import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_reference_field.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';

void main() {
  testWidgets(
      'editor displays the filename while preserving the saved reference and allows replacing it with a shared link',
      (tester) async {
    const reference =
        'browser-file://local/owner/12345678-1234-1234-1234-123456789abc/Planilha.xlsx';
    final controller = TextEditingController(text: reference);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectReferenceField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Arquivo')))));
    expect(find.text('Planilha.xlsx'), findsOneWidget);
    expect(controller.text, reference);
    await tester.tap(find.byTooltip('Remover vínculo'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'https://example.com/planilha');
    expect(controller.text, 'https://example.com/planilha');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  test('browser references preserve filenames and reject unrelated schemes',
      () {
    const reference =
        'browser-folder://local/owner/12345678-1234-1234-1234-123456789abc/Pasta%20do%20Projeto';
    expect(BrowserLocalFiles.isReference(reference), true);
    expect(BrowserLocalFiles.label(reference), 'Pasta do Projeto');
    expect(BrowserLocalFiles.isReference('https://example.com/pasta'), false);
    expect(BrowserLocalFiles.isReference('C:\\Projetos'), false);
    expect(
        BrowserLocalFiles.isReference(
            'browser-folder://evil/owner/12345678-1234-1234-1234-123456789abc/name'),
        false);
    expect(BrowserLocalFiles.isReference('$reference?extra=1'), false);
  });
}
