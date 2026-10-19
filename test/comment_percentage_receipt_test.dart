import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';

void main() {
  test(
      'Comentário confirmado pode ser salvo no app mesmo com porcentagem pendente',
      () {
    final result = EdeskSendResult(
        confirmed: false,
        statusCode: 502,
        message: 'Porcentagem pendente',
        responseBody: jsonEncode({
          'operation': 'comentarios',
          'commentSaved': true,
          'percentageConfirmed': false
        }));
    expect(result.commentPublished, true);
    expect(result.confirmed, false);
    for (final receipt in [
      '',
      '{}',
      '{"commentSaved":true}',
      '{"operation":"comentarios","commentSaved":false}',
      '{"operation":"percentual","commentSaved":true}'
    ]) {
      expect(
          EdeskSendResult(
                  confirmed: false,
                  statusCode: 502,
                  message: '',
                  responseBody: receipt)
              .commentPublished,
          false);
    }
  });
}
