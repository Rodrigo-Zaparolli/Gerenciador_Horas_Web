import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/excel_field_edit_dialog.dart';

void main() {
  testWidgets('editing applies new values without mutating the original', (tester) async {
    final original = {'nome': 'Tabela', 'intervalo': 'A1:B2'};
    Map<String, String>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(onPressed: () async {
        result = await showExcelFieldEditDialog(context, original);
      }, child: const Text('Editar'));
    })));
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Nova tabela');
    await tester.enterText(find.byType(TextFormField).last, "'Maker Checklist-Processo'!a4:b8");
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(result?['nome'], 'Nova tabela');
    expect(result?['intervalo'], "'MAKER CHECKLIST-PROCESSO'!A4:B8");
    expect(original['nome'], 'Tabela');
    expect(tester.takeException(), isNull);
  });
}
