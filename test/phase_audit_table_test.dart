import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/phase_audit_table.dart';
import 'package:gerenciador_horas/features/edesk/work_audit.dart';

void main() {
  const fields = [
    AuditFieldResult('phaseName', '', 'Implantacao', 'Somente consulta'),
    AuditFieldResult('start', '31/07/2026', '31/07/2026', 'Igual'),
    AuditFieldResult('end', '30/11/2026', '15/12/2026', 'Divergencia')
  ];
  for (final width in [390.0, 1200.0]) {
    testWidgets('phase dates stay distinct and safely scroll at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PhaseAuditTable(results: [
        (reference: '2260860/5', error: null, fields: fields)
      ], onAdjust: (ref, _) => selected = ref)))));
      expect(find.text('30/11/2026'), findsNothing); // paired dates in one cell
      expect(find.text('31/07/2026\n30/11/2026'), findsOneWidget);
      expect(find.text('31/07/2026\n15/12/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Ajustar datas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustar datas'));
      expect(selected, '2260860/5');
    });
  }
  testWidgets('busy table cannot launch another operation', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PhaseAuditTable(
                busy: true,
                results: [
                  (reference: '2260860/5', error: null, fields: fields)
                ],
                onAdjust: (reference, fields) => calls++))));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(calls, 0);
  });
}
