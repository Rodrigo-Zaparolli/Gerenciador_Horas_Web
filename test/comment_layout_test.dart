import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_type_selector.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_body_viewport.dart';

void main() {
  testWidgets('Tipo de comentário seleciona externo e conserva tipos padrão',
      (tester) async {
    String value = 'Interno';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 240,
                child: StatefulBuilder(
                    builder: (context, setState) => CommentTypeSelector(
                        value: value,
                        onChanged: (next) => setState(() => value = next)))))));
    await tester.tap(find.text('Externo'));
    await tester.pump();
    expect(value, 'Externo');
    await tester.tap(find.byTooltip('Outros tipos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> &&
        widget.value == 'Padrão (Interno)'));
    await tester.pumpAndSettle();
    expect(value, 'Padrão (Interno)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editor e anexos continuam acessíveis em janela baixa',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                height: 180,
                child: CommentBodyViewport(
                    child: Column(children: [
                  const Expanded(
                      child: TextField(maxLines: null, expands: true)),
                  TextButton(onPressed: () {}, child: const Text('Anexos')),
                ]))))));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Anexos').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
