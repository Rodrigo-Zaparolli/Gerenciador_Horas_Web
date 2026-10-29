import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/work_audit.dart';
import 'package:gerenciador_horas/features/edesk/work_audit_result_card.dart';
import 'package:gerenciador_horas/core/config/work_audit_pilot_access.dart';

void main() {
  test('audit layout remains limited to the pilot account', () {
    expect(
        WorkAuditPilotAccess.allows(
            uid: 'u', email: 'rodrigozaparolli79@gmail.com'),
        isTrue);
    expect(
        WorkAuditPilotAccess.allows(
            uid: 'u', email: 'maiquel.elste@cyncly.com'),
        isFalse);
    expect(
        WorkAuditPilotAccess.allows(
            uid: null, email: 'rodrigozaparolli79@gmail.com'),
        isFalse);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
        'complete consultation is distinct from completed work at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fields = compareAuditWork({}, {
        'name': 'Implantacao',
        'phaseName': 'PROMOB - Implantacao',
        'status': 'Em andamento',
        'start': '01/10/2026',
        'end': '30/10/2026',
        'estimatedHours': '08:00',
        'hours': '08:00',
        'remainingHours': '00:00',
        'overrunHours': '00:00',
        'completed': 'Nao',
      }, auditFields.keys.where((k) => k != 'percentage').toSet());
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: WorkAuditResultCard(
                      reference: '2260860/5', fields: fields)))));
      await tester.pumpAndSettle();
      expect(find.text('Consulta conclu\u00edda'), findsOneWidget);
      expect(find.text('Trabalho n\u00e3o conclu\u00eddo'), findsOneWidget);
      expect(find.text('Trabalho conclu\u00eddo'), findsNothing);
      expect(find.text('00:00'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'date and hour differences show app values beside the E-Desk result',
      (tester) async {
    final fields = compareAuditWork({'start': '02/10/2026', 'hours': '02:00'},
        {'start': '03/10/2026', 'hours': '03:00'}, {'start', 'hours'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkAuditResultCard(
                    reference: '2260860/5', fields: fields)))));
    await tester.pumpAndSettle();
    expect(find.text('Solicita\u00e7\u00e3o 2260860 / Trabalho 5'),
        findsOneWidget);
    expect(find.text('Diverg\u00eancias encontradas'), findsOneWidget);
    expect(find.text('No app: 02/10/2026'), findsOneWidget);
    expect(find.text('No app: 02:00'), findsOneWidget);
  });

  testWidgets('unread hours and completion never appear as zero or success',
      (tester) async {
    final fields = compareAuditWork({}, {'estimatedHours': '08:00'},
        {'estimatedHours', 'hours', 'remainingHours', 'completed'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkAuditResultCard(
                    reference: '2260860/5',
                    fields: fields,
                    error: 'Horas nao consultadas')))));
    await tester.pumpAndSettle();
    expect(find.text('Confer\u00eancia parcial'), findsOneWidget);
    expect(find.text('N\u00e3o consultado'), findsNWidgets(2));
    expect(find.text('00:00'), findsNothing);
    expect(find.text('Conclus\u00e3o n\u00e3o consultada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
