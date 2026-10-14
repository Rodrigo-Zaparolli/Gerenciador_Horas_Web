import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';

void main() {
  test('model recipients separate client, ER and internal audiences', () {
    final contacts = [
      EmailContact(group: 'Cliente', email: 'cliente@example.com'),
      EmailContact(group: 'Cyncly', role: 'Exec. de Relacionamento', email: 'er@example.com'),
      EmailContact(group: 'Cyncly', role: 'Gestor', email: 'gestor@example.com'),
      EmailContact(group: 'Cyncly', name: 'Sem e-mail'),
    ];
    selectModelRecipients(contacts, ProjectEmailKind.initial);
    expect(contacts.map((c) => c.destination), ['Para', 'Não incluir', 'Não incluir', 'Não incluir']);
    selectModelRecipients(contacts, ProjectEmailKind.finalization);
    expect(contacts.map((c) => c.destination), ['Para', 'Cc', 'Não incluir', 'Não incluir']);
    selectModelRecipients(contacts, ProjectEmailKind.internal);
    expect(contacts.map((c) => c.destination), ['Não incluir', 'Para', 'Para', 'Não incluir']);
  });
}
