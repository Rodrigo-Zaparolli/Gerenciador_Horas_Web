import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/client_contacts.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_contact_insert.dart';

class MemoryContacts implements ClientContactStore {
  @override
  bool authorized = true;
  bool fail = false;
  List<ClientContact> values = [];
  @override
  Future<List<ClientContact>> load() async => List.of(values);
  @override
  Future<void> save(ClientContact contact) async {
    if (fail) throw StateError('Sem conexão');
    values.removeWhere((c) => c.id == contact.id);
    values.add(ClientContact(
        id: contact.id.isEmpty ? 'new' : contact.id,
        company: contact.company,
        name: contact.name,
        phone: contact.phone,
        email: contact.email));
  }

  @override
  Future<void> remove(String id) async => values.removeWhere((c) => c.id == id);
}

void main() {
  test('contact validation and insertion preserve rich document and images',
      () {
    const contact = ClientContact(
        id: 'a', company: 'Cliente', name: 'Ana', phone: '(11) 99999-9999');
    expect(contact.validate(), isNull);
    expect(
        const ClientContact(id: '', company: '', name: '', phone: '')
            .validate(),
        isNotNull);
    expect(
        const ClientContact(
                id: '', company: 'Cliente', name: 'Ana', email: 'invalid')
            .validate(),
        isNotNull);
    final controller = quill.QuillController.basic();
    controller.document.insert(0, 'Before after');
    controller.document.insert(12, quill.BlockEmbed.image('image-data'));
    insertClientContact(
        controller, const TextSelection.collapsed(offset: 7), contact);
    expect(controller.document.toPlainText(),
        contains('Before Contato: Ana · (11) 99999-9999after'));
    expect(
        controller.document.toDelta().toJson().any((op) =>
            op['insert'] is Map &&
            (op['insert'] as Map)['image'] == 'image-data'),
        isTrue);
    controller.dispose();
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
        'register, retain failed draft, edit and select contact at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryContacts();
      ClientContact? selected;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('Open'),
                      onPressed: () async {
                        selected = await showDialog<ClientContact>(
                            context: context,
                            builder: (_) => ClientContactsDialog(
                                store: store, company: 'Cliente atual'));
                      })))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cadastrar contato'));
      await tester.pumpAndSettle();
      Finder field(String label) => find.widgetWithText(TextField, label);
      expect(
          tester.widget<TextField>(field('Cliente / empresa')).controller!.text,
          'Cliente atual');
      await tester.enterText(field('Nome do contato'), 'Ana');
      await tester.enterText(field('Telefone / WhatsApp'), '11999999999');
      store.fail = true;
      await tester.tap(find.text('Salvar contato'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem conexão'), findsOneWidget);
      expect(
          tester.widget<TextField>(field('Nome do contato')).controller!.text,
          'Ana');
      store.fail = false;
      await tester.tap(find.text('Salvar contato'));
      await tester.pumpAndSettle();
      expect(store.values.length, 1);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Nome do contato'), 'Ana Silva');
      await tester.tap(find.text('Salvar contato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Silva'));
      await tester.pumpAndSettle();
      expect(selected?.name, 'Ana Silva');
      expect(selected?.phone, '11999999999');
      expect(tester.takeException(), isNull);
    });
  }
}
