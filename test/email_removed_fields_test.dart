import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';

void main() {
  test('three templates omit consultant phone and initial meeting fields', () {
    for (final kind in ProjectEmailKind.values) {
      expect(defaultEmailBody(kind), isNot(contains('{telefone_consultor}')));
    }
    expect(defaultEmailBody(ProjectEmailKind.initial),
        isNot(contains('{data_reuniao}')));
    expect(defaultEmailBody(ProjectEmailKind.initial),
        isNot(contains('{hora_reuniao}')));
  });
  test('older templates and drafts remove only requested fields', () {
    expect(cleanRemovedEmailFields(
        'Telefone cliente: 123\nNossa primeira reunião está agendada para o dia 01/10/2026, às 08:00.\nAtt,\nConsultor\n123\nSite',
        ProjectEmailKind.initial, consultantPhone: '123'),
        'Telefone cliente: 123\nAtt,\nConsultor\nSite');
    expect(cleanRemovedEmailFields('Telefone: {telefone_consultor}\nResumo',
        ProjectEmailKind.internal), 'Resumo');
  });
}
