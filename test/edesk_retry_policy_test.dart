import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_python_web.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gerenciador_horas/data/services/edesk_retry_policy.dart';

void main() {
  test('Manual hours retry reaches integration instead of previous-attempt block', () async {
    var posts = 0;
    final result = await EdeskWebClient(
      apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response('{"mode":"local"}', 200);
        posts++;
        expect(request.url.path, '/api/edesk/horas');
        final body = jsonDecode(request.body) as Map;
        if (body['retryUncertain'] != true) {
          return http.Response('{"confirmed":false,"message":"Previous attempt"}', 409);
        }
        return http.Response('{"confirmed":true,"message":"ok"}', 200);
      }),
    ).execute(requestJson: '{"trabalhos":[]}', enviar: true,
      script: 'edesk_horas.py',
      retryUncertain: retryUnconfirmedHours(script: 'edesk_horas.py', sending: true));
    expect(posts, 1);
    expect(result.confirmed, true);
  });
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
