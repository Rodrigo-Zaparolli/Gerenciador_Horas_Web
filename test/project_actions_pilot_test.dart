import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_actions_pilot.dart';

void main() {
  testWidgets('Compact actions route every menu item to its own callback',
      (tester) async {
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
    await tester.tap(find.text('Pasta'));
    expect(selected, 'folder');
    for (final item
        in {'Abrir no Excel': 'open', 'Editar no sistema': 'edit'}.entries) {
      await tester.tap(find.text('Planilha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.key));
      await tester.pumpAndSettle();
      expect(selected, item.value);
    }
    for (final item in {
      'Editar trabalho': 'work',
      'Checklist': 'check',
      'Comentários': 'comment',
      'E-mails': 'email'
    }.entries) {
      await tester.tap(find.byTooltip('Mais ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.key));
      await tester.pumpAndSettle();
      expect(selected, item.value);
    }
    expect(tester.takeException(), isNull);
  });
}
