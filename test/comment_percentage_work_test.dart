import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_percentage_work.dart';

TaskModel task(String id, String name) => TaskModel(
    subId: id,
    stage: name,
    status: 'TRAB',
    startDate: DateTime(2026, 10, 17),
    estimatedHours: '08:00',
    hourType: 'Hs Cobradas',
    edeskIdTrabalho: id);

void main() {
  testWidgets(
      'Porcentagem do comentário usa o trabalho escolhido, sem assumir o primeiro',
      (tester) async {
    final first = task('1', 'Gerência');
    final second = task('6', 'Pós-Implantação');
    TaskModel? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      selected = await chooseCommentPercentageWork(
                          context, [first, second]);
                    },
                    child: const Text('Enviar'))))));
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(selected, null);
    await tester.tap(find.text('Pós-Implantação · Trabalho 6'));
    await tester.pumpAndSettle();
    expect(selected, same(second));
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(selected, null);
  });
}
