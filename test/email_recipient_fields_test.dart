import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';

void main() {
  testWidgets(
      'Company selection fills name and email without duplicating Para in Cc',
      (tester) async {
    final contacts = <EmailContact>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => EmailRecipientFields(
                    contacts: contacts,
                    onChanged: () => setState(() {}),
                    pickCompanyContact: () async => EmailContact(
                        name: 'Ana', email: 'ana@empresa.com'))))));
    await tester.tap(find.byTooltip('Buscar colaborador para Para'));
    await tester.pumpAndSettle();
    expect(contacts.single.name, 'Ana');
    expect(contacts.single.destination, 'Para');
    expect(find.text('Ana\nana@empresa.com'), findsOneWidget);
    await tester.tap(find.byTooltip('Buscar colaborador para Cc'));
    await tester.pumpAndSettle();
    expect(contacts, hasLength(1));
    expect(contacts.single.destination, 'Para');
    expect(find.textContaining('Este contato já está em Para'), findsOneWidget);
  });
  for (final width in [360.0, 1000.0]) {
    testWidgets(
        'all imported addresses wrap and remain reachable at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final contacts = List.generate(
          16,
          (i) => EmailContact(
              name: 'Contato importado $i',
              email: 'contato$i@example.com',
              destination: i < 8 ? 'Para' : 'Cc'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: EmailRecipientFields(
                      contacts: contacts, onChanged: () {})))));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(16));
      final first = find.text('Contato importado 0\ncontato0@example.com');
      final eighth = find.text('Contato importado 7\ncontato7@example.com');
      expect(
          tester.getRect(eighth).top, greaterThan(tester.getRect(first).top));
      final last = find.text('Contato importado 15\ncontato15@example.com');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      for (final chip in tester.widgetList<InputChip>(find.byType(InputChip))) {
        final bounds = tester.getRect(find.byWidget(chip));
        expect(bounds.left, greaterThanOrEqualTo(12));
        expect(bounds.right, lessThanOrEqualTo(width - 12));
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Para and Cc exclude each other, including typed emails and add all',
      (tester) async {
    final contacts = [
      EmailContact(
          name: 'Cliente', email: 'cliente@example.com', group: 'Cliente')
    ];
    final key = GlobalKey<EmailRecipientFieldsState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => EmailRecipientFields(
                    key: key,
                    contacts: contacts,
                    onChanged: () => setState(() {}))))));
    Finder field(String label) =>
        find.byKey(ValueKey('recipient-input-$label'));
    await tester.enterText(
        field('Para'), 'CLIENTE@example.com;novo@example.com');
    expect(key.currentState!.commitPending(), isTrue);
    await tester.pumpAndSettle();
    expect(contacts.length, 2);
    expect(contacts.where((c) => c.destination == 'Para').length, 2);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('recipient-container-Para')),
            matching: find.byType(InputChip)),
        findsNWidgets(2));
    await tester.enterText(field('Cc'), 'cliente@example.com');
    expect(key.currentState!.commitPending(), isFalse);
    await tester.pumpAndSettle();
    expect(contacts.length, 2);
    expect(contacts.first.destination, 'Para');
    await tester.enterText(field('Cc'), '');
    await tester.enterText(field('Para'), 'endereco-invalido');
    expect(key.currentState!.commitPending(), isFalse);
    await tester.pumpAndSettle();
    expect(contacts.length, 2);
    expect(find.textContaining('Informe e-mails válidos'), findsOneWidget);
    await tester.enterText(field('Para'), '');
    expect(key.currentState!.commitPending(), isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adicionar em Para'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente — cliente@example.com'), findsNothing);
    expect(find.text('Adicionar todos'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(contacts.first.destination, 'Para');
    contacts.add(EmailContact(name: 'Disponível', email: 'livre@example.com'));
    await tester.tap(find.byTooltip('Adicionar em Cc'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente — cliente@example.com'), findsNothing);
    await tester.tap(find.text('Adicionar todos'));
    await tester.pumpAndSettle();
    expect(contacts.length, 3);
    expect(contacts.first.destination, 'Para');
    expect(contacts[1].destination, 'Para');
    expect(contacts.last.destination, 'Cc');
    expect(tester.takeException(), isNull);
  });
}
