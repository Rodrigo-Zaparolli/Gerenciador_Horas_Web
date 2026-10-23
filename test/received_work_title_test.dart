import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work.dart';

void main() {
  final enterprise = WorkFormat(id: 'e', name: 'Promob Enterprise');
  final professional = WorkFormat(id: 'p', name: 'Professional');
  final formats = [enterprise, professional];
  test('request product segment resolves the registered Enterprise type', () {
    expect(
        receivedFormatForTitle(
            'Revitalização de base - Enterprise Produção completa - Promob BR Cantanhede Moveis',
            formats),
        same(enterprise));
    expect(
        receivedFormatForTitle(
            'Professional Produção Completa - Cliente', formats),
        same(professional));
  });
  test('customer words and partial product names do not select a type', () {
    expect(receivedFormatForTitle('Consultoria - Enterprise', formats), isNull);
    expect(receivedFormatForTitle('EnterpriseX - Cliente', formats), isNull);
    expect(receivedFormatForTitle('', formats), isNull);
  });
  test('ambiguous configured aliases require manual selection', () {
    expect(
        receivedFormatForTitle('Enterprise Produção completa - Cliente',
            [enterprise, WorkFormat(id: 'e2', name: 'Enterprise')]),
        isNull);
  });
}
