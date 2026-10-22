import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'package:gerenciador_horas/features/edesk/received_work.dart';
import 'received_work_store_test.dart' show ImportAuth;

class ReviewAuth extends ImportAuth {
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> authStateChanges() => changes.stream;
}

void main() {
  testWidgets(
      'account change removes its own review without popping another route',
      (tester) async {
    final auth = ReviewAuth();
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigation,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ReceivedWorkReview(
                            summary: const {'solicitacao': '226144'},
                            details: const [],
                            types: const [],
                            auth: auth)),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    navigation.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Outra tela'))));
    await tester.pumpAndSettle();
    auth.user = null;
    auth.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Outra tela'), findsOneWidget);
    expect(find.byType(ReceivedWorkReview), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
  });
  for (final width in [390.0, 1300.0]) {
    testWidgets(
        'review requires hours and imports only a selected new work at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ProjectModel? saved;
      int? count;
      final existing = receivedProject(
          request: '226144',
          client: 'Cliente',
          type: 'Professional',
          leader: 'Líder',
          receivedAt: DateTime(2026, 10, 22),
          hourType: 'Hs Cobradas',
          steps: [
            {'id': '3', 'name': 'Implantação', 'hours': '08:00'}
          ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        count = await showDialog<int>(
                            context: context,
                            builder: (_) => ReceivedWorkReview(
                                  summary: const {'solicitacao': '226144'},
                                  types: const ['Professional'],
                                  existing: existing,
                                  auth: ImportAuth(),
                                  details: const [
                                    {
                                      'idTrabalho': '3',
                                      'values': {
                                        'name': 'Implantação',
                                        'estimatedHours': '08:00'
                                      }
                                    },
                                    {
                                      'idTrabalho': '6',
                                      'values': {'name': 'Pós-implantação'}
                                    }
                                  ],
                                  importProject: (project) async {
                                    saved = project;
                                    return 1;
                                  },
                                ));
                      },
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cadastrar no app'));
      await tester.pumpAndSettle();
      expect(saved, isNull,
          reason: 'Missing planned hours must stop before any write');
      final hours = find.byWidgetPredicate((widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Horas previstas *' &&
          widget.enabled == true);
      await tester.ensureVisible(hours);
      await tester.enterText(hours, '02:30');
      await tester.pump();
      await tester.tap(find.text('Cadastrar no app'));
      await tester.pumpAndSettle();
      expect(count, 1);
      expect(saved!.subTasks, hasLength(1));
      expect(saved!.subTasks!.single.edeskWorkNumber, '6');
      expect(saved!.estimatedHours, '02:30');
      expect(saved!.serviceType, 'Professional');
      expect(saved!.leader, 'Líder');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
