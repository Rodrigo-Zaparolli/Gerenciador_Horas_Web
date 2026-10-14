import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';

void main() {
  testWidgets('Para and Cc exclude each other, including typed emails and add all', (tester) async {
    final contacts = [EmailContact(name: 'Cliente', email: 'cliente@example.com', group: 'Cliente')];
    final key = GlobalKey<EmailRecipientFieldsState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, setState) => EmailRecipientFields(key: key,
            contacts: contacts, onChanged: () => setState(() {}))))));
    Finder field(String label) => find.byKey(ValueKey('recipient-input-$label'));
    await tester.enterText(field('Para'), 'CLIENTE@example.com;novo@example.com');
    expect(key.currentState!.commitPending(), isTrue);
    await tester.pumpAndSettle();
    expect(contacts.length, 2);
    expect(contacts.where((c) => c.destination == 'Para').length, 2);
    expect(find.descendant(of: find.byKey(const ValueKey('recipient-container-Para')),
        matching: find.byType(InputChip)), findsNWidgets(2));
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
