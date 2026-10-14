import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gerenciador_horas/data/services/edesk_endpoint.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';
import 'package:gerenciador_horas/features/edesk/edesk_central_dialog.dart';

void main() {
  final factory = EdeskIntegrationApi.clientFactory;
  final token = EdeskIntegrationApi.tokenProvider;
  final provider = EdeskIntegrationApi.urlProvider;
  tearDown(() {
    EdeskIntegrationApi.clientFactory = factory;
    EdeskIntegrationApi.tokenProvider = token;
    EdeskIntegrationApi.urlProvider = provider;
  });

  testWidgets(
      'autorizar este PC usa loopback e salva endereço para a conta, sem enviar horas',
      (tester) async {
    Map<String, dynamic>? saved;
    final requests = <http.Request>[];
    EdeskIntegrationApi.tokenProvider = () async => 'owner-token';
    EdeskIntegrationApi.clientFactory = () => MockClient((request) async {
          requests.add(request);
          expect(request.url.host, '127.0.0.1');
          expect(request.url.path, '/api/edesk/central/pair');
          return http.Response(
              jsonEncode(
                  {'url': 'http://192.168.1.10:8765', 'authorized': true}),
              200);
        });
    final settings = EdeskEndpointSettings(
        uidProvider: () => 'owner',
        read: (_) async => null,
        write: (uid, value) async {
          expect(uid, 'owner');
          saved = value;
        });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskCentralDialog(
                settings: settings, uidProvider: () => 'owner'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autorizar este PC como central'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(saved, {'mode': 'central', 'url': 'http://192.168.1.10:8765'});
    expect(
        find.textContaining('Computador central autorizado.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('conta não autorizada não altera a configuração', (tester) async {
    var writes = 0;
    EdeskIntegrationApi.tokenProvider = () async => 'token';
    EdeskIntegrationApi.clientFactory = () => MockClient((request) async {
          expect(request.url.host, '192.168.1.10');
          return request.url.path == '/healthz'
              ? http.Response(
                  '{"service":"gerenciador-horas-edesk","status":"ok"}', 200)
              : http.Response('{"message":"Conta não autorizada"}', 403,
                  headers: {'content-type': 'application/json; charset=utf-8'});
        });
    final settings = EdeskEndpointSettings(
        uidProvider: () => 'user',
        read: (_) async =>
            {'mode': 'central', 'url': 'http://192.168.1.10:8765'},
        write: (uid, value) async {
          writes++;
        });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskCentralDialog(
                settings: settings, uidProvider: () => 'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar configuração'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Conta não autorizada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('configuração central cabe em celular sem esconder ações',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = EdeskEndpointSettings(
        uidProvider: () => 'user',
        read: (_) async =>
            {'mode': 'central', 'url': 'http://192.168.1.10:8765'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskCentralDialog(
                settings: settings, uidProvider: () => 'user'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Salvar configuração'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('status e histórico usam o mesmo endereço dinâmico e caminho base',
      () async {
    EdeskIntegrationApi.tokenProvider = () async => 'token';
    EdeskIntegrationApi.urlProvider = () async => 'https://example.com/central';
    EdeskIntegrationApi.clientFactory = () => MockClient((request) async {
          expect(request.url.toString(),
              'https://example.com/central/api/edesk/history');
          expect(request.headers['authorization'], 'Bearer token');
          return http.Response('{"items":{}}', 200);
        });
    expect(await EdeskIntegrationApi.call('/api/edesk/history'), {'items': {}});
  });
}
