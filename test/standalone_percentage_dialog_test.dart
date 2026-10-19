import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/standalone_percentage_dialog.dart';

TaskModel task(String id, String name) => TaskModel(
    subId: id,
    stage: name,
    status: 'TRAB',
    startDate: DateTime(2026, 10, 16),
    estimatedHours: '08:00',
    hourType: 'Hs Cobradas',
    edeskIdTrabalho: id);

void main() {
  testWidgets(
      'percentage alone chooses the work, validates and sends without any comment editor',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tasks = [task('1', 'Contato Inicial'), task('3', 'Implantação')..edeskIdTrabalho = '2'];
    TaskModel? sent;
    double? percent;
    await tester.pumpWidget(MaterialApp(
        home: StandalonePercentageDialog(
            tasks: tasks,
            initialValue: '',
            canSend: () => true,
            onSend: (work, value) async {
              sent = work;
              percent = value;
              return const EdeskSendResult(
                  confirmed: false,
                  statusCode: 503,
                  message: 'Atualize a integração.',
                  responseBody: '');
            })));
    await tester.tap(find.text('Conferir e enviar'));
    await tester.pumpAndSettle();
    expect(sent, isNull);
    expect(find.text('Informe a porcentagem.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '101');
    await tester.tap(find.text('Conferir e enviar'));
    await tester.pumpAndSettle();
    expect(sent, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<TaskModel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Implantação · 3').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '91,5');
    await tester.tap(find.text('Conferir e enviar'));
    await tester.pumpAndSettle();
    expect(sent, same(tasks[1]));
    expect(sent?.edeskWorkNumber, '3');
    expect(percent, 91.5);
    expect(find.text('Atualize a integração.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero percent is valid and success returns only that value',
      (tester) async {
    double? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<double>(
                          context: context,
                          builder: (_) => StandalonePercentageDialog(
                              tasks: [task('6', 'Implantação')],
                              initialValue: '0',
                              canSend: () => true,
                              onSend: (_, value) async {
                                expect(value, 0);
                                return const EdeskSendResult(
                                    confirmed: true,
                                    statusCode: 200,
                                    message: 'Confirmado',
                                    responseBody: '');
                              }));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferir e enviar'));
    await tester.pumpAndSettle();
    expect(result, 0);
    expect(find.byType(StandalonePercentageDialog), findsNothing);
  });
  testWidgets('account changes block percentage sending', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StandalonePercentageDialog(
            tasks: [task('6', 'Implantação')],
            initialValue: '25',
            canSend: () => false,
            onSend: (work, value) async => throw StateError('Must not send'))));
    await tester.tap(find.text('Conferir e enviar'));
    await tester.pumpAndSettle();
    expect(find.text('A conta mudou. Feche e abra novamente.'), findsOneWidget);
  });
}
