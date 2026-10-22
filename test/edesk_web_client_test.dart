import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_python_web.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Read-only queries supply the required portal URL and preserve an explicit URL', () async {
    for (final action in ['conferencia', 'recebidos']) {
      for (final url in [null, '', 'https://promob.e-desk.com.br/Portal/']) {
        final result = await EdeskWebClient(
          apiUrl: 'http://127.0.0.1:8765', tokenProvider: () async => 'token',
          client: MockClient((request) async {
            if (request.method == 'GET') return http.Response('{"workAudit":true,"workInbox":true}', 200);
            final body = jsonDecode(request.body);
            expect(body['request']['url'], url == null || url.isEmpty ? 'https://promob.e-desk.com.br' : url);
            expect(body['enviar'], false);
            return http.Response('{"confirmed":true,"responseBody":"{}"}', 200);
          }),
        ).execute(requestJson: jsonEncode({'url': url}), enviar: false,
          script: action == 'conferencia' ? 'edesk_conferencia.py' : 'edesk_recebidos.py');
        expect(result.confirmed, true);
      }
    }
  });
  test('Received works require native support and always use a read-only request', () async {
    var supported=false;
    final client=EdeskWebClient(apiUrl:'http://127.0.0.1:8765',tokenProvider:()async=>'token',client:MockClient((request)async{
      if(request.method=='GET')return http.Response(jsonEncode({'workInbox':supported}),200);
      expect(request.url.path,'/api/edesk/recebidos');expect(jsonDecode(request.body)['enviar'],false);
      return http.Response(jsonEncode({'confirmed':true,'responseBody':jsonEncode({'rows':[],'complete':true})}),200);
    }));
    expect((await client.execute(requestJson:'{}',enviar:false,script:'edesk_recebidos.py')).statusCode,503);
    expect((await client.execute(requestJson:'{}',enviar:true,script:'edesk_recebidos.py')).statusCode,400);
    supported=true;
    expect((await client.execute(requestJson:'{}',enviar:false,script:'edesk_recebidos.py')).confirmed,true);
  });
  test('Audit is read-only and requires the new native capability', () async {
    final calls = <String>[];
    final client = EdeskWebClient(apiUrl: 'http://127.0.0.1:8765', tokenProvider: () async => 'token',
      client: MockClient((request) async {
        calls.add(request.method);
        return http.Response('{"mode":"local"}',200);
      }));
    final rejected = await client.execute(requestJson:'{}',enviar:true,script:'edesk_conferencia.py');
    expect(rejected.statusCode,400);
    expect(calls,isEmpty);
    final outdated = await client.execute(requestJson:'{}',enviar:false,script:'edesk_conferencia.py');
    expect(outdated.statusCode,503);
    expect(calls,['GET']);
  });
  test('Audit posts a read-only request to its dedicated endpoint', () async {
    final result = await EdeskWebClient(apiUrl:'http://127.0.0.1:8765',tokenProvider:() async=>'token',
      client:MockClient((request) async {
        if(request.method=='GET') return http.Response('{"workAudit":true,"mode":"local"}',200);
        expect(request.url.path,'/api/edesk/conferencia');
        expect(jsonDecode(request.body)['enviar'],false);
        return http.Response(jsonEncode({'confirmed':true, 'responseBody':jsonEncode({'ok':true,'operation':'conferencia','rows':[]})}),200);
      })).execute(requestJson:'{}',enviar:false,script:'edesk_conferencia.py');
    expect(result.confirmed,true);
  });
  test('Hours require persisted receipt support before any POST', () async {
    final methods = <String>[];
    final result = await EdeskWebClient(
      apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'token',
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response('{"mode":"local"}', 200);
      }),
    ).execute(requestJson: '{}', enviar: true, script: 'edesk_horas.py');
    expect(result.confirmed, false);
    expect(result.statusCode, 503);
    expect(methods, ['GET']);
    expect(result.message, contains('v36'));
  });

  test('Hours propagate persisted receipt success from the integration', () async {
    final methods = <String>[];
    final result = await EdeskWebClient(
      apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'token',
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response(request.method == 'GET'
            ? '{"mode":"local","hoursReconciliation":true}'
            : '{"confirmed":true,"message":"Cadastro finalizado com sucesso"}', 200);
      }),
    ).execute(requestJson: '{}', enviar: true, script: 'edesk_horas.py');
    expect(result.confirmed, true);
    expect(methods, ['GET', 'POST']);
  });

  test('standalone percentage never posts to an old integration', () async {
    final calls = <http.Request>[];
    final result = await EdeskWebClient(apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'token', client: MockClient((request) async {
        calls.add(request);
        return http.Response('{"commentPercentage":true}', 200);
      })).execute(requestJson: '{"percentualRealizado":25}', enviar: true, script: 'edesk_percentual.py');
    expect(result.confirmed, false); expect(result.statusCode, 503);
    expect(calls.every((request) => request.method == 'GET'), true);
  });
  test('standalone percentage uses its own endpoint without comment content', () async {
    final calls = <http.Request>[];
    final result = await EdeskWebClient(apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'token', client: MockClient((request) async {
        calls.add(request);
        if (request.method == 'GET') return http.Response('{"standalonePercentage":true,"commentPercentage":true}', 200);
        expect(request.url.path, '/api/edesk/percentual');
        final data = jsonDecode(request.body)['request'] as Map;
        expect(data.containsKey('texto'), false); expect(data.containsKey('imagemBase64'), false);
        return http.Response('{"confirmed":true,"message":"Porcentagem confirmada"}', 200);
      })).execute(requestJson: '{"solicitacao":"226144","idTrabalho":"6","percentualRealizado":0}',
          enviar: true, script: 'edesk_percentual.py');
    expect(result.confirmed, true); expect(calls.where((request) => request.method == 'POST'), hasLength(1));
  });
  test(
      'Old integration cannot silently ignore the percentage or save the comment',
      () async {
    final calls = <http.Request>[];
    final result = await EdeskWebClient(
            apiUrl: 'http://127.0.0.1:8765',
            tokenProvider: () async => 'test-token',
            client: MockClient((request) async {
              calls.add(request);
              return http.Response(jsonEncode({'mode': 'local'}), 200);
            }))
        .execute(
            requestJson: '{"percentualRealizado":25}',
            enviar: true,
            script: 'edesk_comentario.py');
    expect(result.confirmed, isFalse);
    expect(result.statusCode, 503);
    expect(calls.length, 1);
    expect(calls.single.method, 'GET');
  });
  test('Supported integration receives zero percent as well as the comment',
      () async {
    final calls = <http.Request>[];
    final result = await EdeskWebClient(
            apiUrl: 'http://127.0.0.1:8765',
            tokenProvider: () async => 'test-token',
            client: MockClient((request) async {
              calls.add(request);
              return http.Response(
                  jsonEncode(request.method == 'GET'
                      ? {'mode': 'local', 'commentPercentage': true, 'commentPercentageReceipt': true}
                      : {'confirmed': true, 'message': 'ok'}),
                  200);
            }))
        .execute(
            requestJson: '{"percentualRealizado":0,"texto":"Comentario"}',
            enviar: true,
            script: 'edesk_comentario.py');
    expect(result.confirmed, isTrue);
    expect(calls.length, 2);
    expect(jsonDecode(calls.last.body)['request']['percentualRealizado'], 0);
  });

  test('Files-only service does not receive hours or claim a confirmed send',
      () async {
    final requests = <http.Request>[];
    final result = await EdeskWebClient(
      apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({'mode': 'files-only', 'status': 'ok'}), 200);
      }),
    ).execute(requestJson: '{}', enviar: true, script: 'edesk_horas.py');
    expect(requests.length, 1);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/healthz');
    expect(result.confirmed, isFalse);
    expect(result.message, contains('extensão E-Desk'));
  });
  test('Serviço local desligado informa como iniciar e não confirma envio',
      () async {
    final result = await EdeskWebClient(
      apiUrl: 'http://127.0.0.1:8765',
      tokenProvider: () async => 'test-token',
      client: MockClient((_) async => throw http.ClientException('offline')),
    ).execute(requestJson: '{}', enviar: true, script: 'edesk_horas.py');
    expect(result.confirmed, isFalse);
    expect(result.statusCode, 503);
    expect(result.message, contains('Iniciar integração E-Desk'));
  });
  test('Envia rotas, token Firebase e intenção de envio corretamente',
      () async {
    for (final entry in {
      'edesk_fases.py': 'fases',
      'edesk_horas.py': 'horas',
      'edesk_comentario.py': 'comentarios'
    }.entries) {
      http.Request? sentRequest;
      final client = EdeskWebClient(
        apiUrl: 'https://example.com/backend/',
        tokenProvider: () async => 'test-token',
        client: MockClient((request) async {
          sentRequest = request;
          return http.Response(
              jsonEncode({
                'confirmed': true,
                'message': 'Concluído',
                'responseBody': 'payload'
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final result = await client.execute(
          requestJson: '{"texto":"Olá"}', enviar: false, script: entry.key);
      expect(sentRequest?.url.toString(),
          'https://example.com/backend/api/edesk/${entry.value}');
      expect(sentRequest?.headers['authorization'], 'Bearer test-token');
      expect(jsonDecode(sentRequest!.body), {
        'request': {'texto': 'Olá'},
        'enviar': false
      });
      expect(result.confirmed, isTrue, reason: result.message);
      expect(result.responseBody, 'payload');
    }
  });

  test('Configuração e autenticação inválidas não enviam dados', () async {
    final transport =
        MockClient((_) async => throw StateError('Não deve enviar dados'));
    for (final url in ['', 'http://example.com', 'javascript:alert(1)']) {
      final result = await EdeskWebClient(apiUrl: url, client: transport)
          .execute(requestJson: '{}', enviar: true, script: 'edesk_horas.py');
      expect(result.confirmed, isFalse);
      expect(result.statusCode, 503);
    }
    final unauthenticated = EdeskWebClient(
        apiUrl: 'https://example.com',
        client: transport,
        tokenProvider: () async => null);
    expect(
        (await unauthenticated.execute(
                requestJson: '{}', enviar: true, script: 'edesk_horas.py'))
            .statusCode,
        401);
    expect(
        (await unauthenticated.execute(
                requestJson: '{', enviar: true, script: 'edesk_horas.py'))
            .statusCode,
        400);
  });

  test('HTTP de falha nunca confirma operação mesmo com confirmed true',
      () async {
    final client = EdeskWebClient(
        apiUrl: 'http://localhost:8080',
        tokenProvider: () async => 'token',
        client: MockClient((_) async =>
            http.Response('{"confirmed":true,"message":"Falha"}', 502)));
    final result = await client.execute(
        requestJson: '{}', enviar: true, script: 'edesk_fases.py');
    expect(result.confirmed, isFalse);
    expect(result.statusCode, 502);
  });

  test('Timeout informa que é necessário conferir antes de reenviar', () async {
    final client = EdeskWebClient(
        apiUrl: 'https://example.com',
        tokenProvider: () async => 'token',
        client: MockClient((_) async => throw TimeoutException('timeout')));
    final result = await client.execute(
        requestJson: '{}', enviar: true, script: 'edesk_fases.py');
    expect(result.confirmed, isFalse);
    expect(result.statusCode, 504);
    expect(result.message, contains('antes de reenviar'));
  });
}
