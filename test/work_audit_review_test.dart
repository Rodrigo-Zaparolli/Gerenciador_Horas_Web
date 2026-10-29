import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/work_audit_review.dart';
import 'package:gerenciador_horas/features/edesk/work_audit.dart';
import 'work_audit_test.dart' as fixtures;

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets(
        'project context hides scope controls and keeps results accessible at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var runs = 0;
      await tester.pumpWidget(MaterialApp(
          home: WorkAuditReview(
              project: fixtures.project(),
              results: const [],
              options: const Text('Campos opcionais'),
              scopeControls: const Text('Pesquisar projeto'),
              busy: false,
              message: '',
              progress: '',
              onRun: () => runs++,
              onClose: () {},
              onAdjust: (ref, fields) {})));
      expect(find.text('Pesquisar projeto'), findsNothing);
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Campos opcionais'), findsNothing);
      expect(find.text('Fases e datas'), findsOneWidget);
      await tester.tap(find.text('Trabalhos e horas'));
      await tester.pumpAndSettle();
      expect(find.text('Horas e situa\u00e7\u00e3o em um s\u00f3 lugar'),
          findsOneWidget);
      await tester.tap(find.text('Iniciar confer\u00eancia'));
      expect(runs, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed request uses a compact notice without six empty metrics',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: WorkAuditReview(
            project: fixtures.project(),
            results: [
              (
                reference: '226144',
                error: 'A solicitacao nao terminou de abrir no E-Desk.',
                fields: compareAuditWork({}, {}, auditFields.keys.toSet())
              )
            ],
            options: const SizedBox(),
            scopeControls: const SizedBox(),
            busy: false,
            message: '',
            progress: '',
            onRun: () {},
            onClose: () {},
            onAdjust: (ref, fields) {})));
    await tester.tap(find.text('Trabalhos e horas'));
    await tester.pumpAndSettle();
    expect(find.text('A solicitacao nao terminou de abrir no E-Desk.'),
        findsOneWidget);
    expect(find.text('N\u00e3o consultado'), findsNothing);
    expect(find.text('00:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
