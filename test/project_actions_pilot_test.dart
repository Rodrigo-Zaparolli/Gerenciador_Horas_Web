import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_actions_pilot.dart';

void main() {
  testWidgets('Compact actions route every menu item to its own callback',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectActionsPilot(
                hasFolder: true,
                hasExcel: true,
                onFolder: () => selected = 'folder',
                onExcel: () => selected = 'open',
                onEditSpreadsheet: () => selected = 'edit',
                onEditWork: () => selected = 'work',
                onChecklist: () => selected = 'check',
                onComment: () => selected = 'comment',
                onEmail: () => selected = 'email'))));
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('Pasta'), findsNothing);
    expect(find.text('Planilha'), findsNothing);
    for (final item in {
      'Abrir pasta': 'folder',
      'Abrir planilha no Excel': 'open',
      'Editar planilha no sistema': 'edit',
      'Editar trabalho': 'work',
      'Checklist': 'check',
      'Comentários': 'comment',
      'E-mails': 'email'
    }.entries) {
      await tester.tap(find.byTooltip('Ações do projeto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.key));
      await tester.pumpAndSettle();
      expect(selected, item.value);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectActionsPilot(
                hasFolder: false,
                hasExcel: false,
                onFolder: () => selected = 'folder',
                onExcel: () => selected = 'open',
                onEditSpreadsheet: () => selected = 'edit',
                onEditWork: () => selected = 'work',
                onChecklist: () => selected = 'check',
                onComment: () => selected = 'comment',
                onEmail: () => selected = 'email'))));
    await tester.tap(find.byTooltip('Ações do projeto'));
    await tester.pumpAndSettle();
    final entries = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>));
    expect(
        entries
            .where((e) => ['folder', 'open', 'spreadsheet'].contains(e.value))
            .every((e) => !e.enabled),
        isTrue);
    expect(
        entries
            .where(
                (e) => ['work', 'check', 'comment', 'email'].contains(e.value))
            .every((e) => e.enabled),
        isTrue);
  });
}
