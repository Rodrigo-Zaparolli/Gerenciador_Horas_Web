import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_retry_policy.dart';

void main() {
  test('Somente nova confirmação de horas libera tentativa sem confirmação',
      () {
    expect(
        retryUnconfirmedHours(script: 'edesk_horas.py', sending: true), true);
    expect(
        retryUnconfirmedHours(script: 'edesk_horas.py', sending: false), false);
    for (final script in [
      'edesk_comentario.py',
      'edesk_fases.py',
      'edesk_percentual.py'
    ]) {
      expect(retryUnconfirmedHours(script: script, sending: true), false);
    }
  });
}
