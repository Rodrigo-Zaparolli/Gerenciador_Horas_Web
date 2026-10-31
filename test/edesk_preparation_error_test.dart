import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gerenciador_horas/data/services/edesk_integration.dart';

void main() {
  test('consultation distinguishes malformed results from login errors', () {
    expect(edeskConsultationError(const FormatException('private response')),
        contains('dados inv\u00e1lidos'));
    expect(edeskConsultationError(StateError('Entre novamente.')),
        'Entre novamente.');
    expect(edeskConsultationError(Exception('password=secret')),
        isNot(contains('secret')));
  });
  test('preparation shows the actual busy and authentication reasons', () {
    expect(edeskPreparationError(StateError('Há outro envio em andamento.')),
        'Há outro envio em andamento.');
    expect(edeskPreparationError(StateError('Entre novamente na sua conta.')),
        'Entre novamente na sua conta.');
  });
  test('connection failures offer startup without claiming another send', () {
    for (final error in [
      TimeoutException('test'),
      http.ClientException('test')
    ]) {
      final message = edeskPreparationError(error);
      expect(message, contains('Iniciar integração E-Desk.cmd'));
      expect(message, isNot(contains('outro envio')));
    }
  });
}
