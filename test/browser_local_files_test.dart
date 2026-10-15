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
  testWidgets(
      'full paths stay with their project when switching editor controllers',
      (tester) async {
    const paths = [
      r'C:\Clientes\226144 - Orquinare\Documentos',
      r'C:\Clientes\Sin Moveis Planejados\Documentos'
    ];
    final refs = List.generate(
        2,
        (i) => Uri(scheme: 'desktop-folder', host: 'local', pathSegments: [
              'owner',
              '12345678-1234-1234-1234-123456789ab$i',
              paths[i]
            ]).toString());
    final controllers =
        refs.map((r) => TextEditingController(text: r)).toList();
    for (final index in [0, 1, 0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: ProjectReferenceField(
                      controller: controllers[index],
                      decoration:
                          const InputDecoration(labelText: 'Pasta'))))));
      expect(BrowserLocalFiles.isReference(refs[index]), true);
      expect(find.text(paths[index]), findsOneWidget);
      expect(controllers[0].text, refs[0]);
      expect(controllers[1].text, refs[1]);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    for (final controller in controllers) {
      controller.dispose();
    }
  });
  test('full spreadsheet paths retain spaces accents and URI delimiters', () {
    const path = r'C:\Clientes\Orquinare\Implantação #1 %.xlsx';
    final ref = Uri(scheme: 'desktop-file', host: 'local', pathSegments: [
      'owner',
      '12345678-1234-1234-1234-123456789abc',
      path
    ]).toString();
    expect(BrowserLocalFiles.isReference(ref), true);
    expect(BrowserLocalFiles.label(ref), path);
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
