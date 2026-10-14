import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';
import 'package:gerenciador_horas/features/backup/backup_dialog.dart';

void main() {
  final originalFactory = EdeskIntegrationApi.clientFactory;
  final originalToken = EdeskIntegrationApi.tokenProvider;
  final data = {
    'trabalhos': [
      {
        'solicitacao': '123',
        'idTrabalho': '2',
        'horas': [
          {
            'data': '08/10/2026',
            'inicio': '08:00',
            'fim': '09:00',
            'descricao': 'Revisão'
          }
        ]
      }
    ]
  };
  var state = 'new';
  setUp(() {
    state = 'new';
    EdeskIntegrationApi.tokenProvider = () async => 'test';
    EdeskIntegrationApi.clientFactory = () => MockClient((request) async {
          if (request.url.path == '/api/edesk/history') {
            state = 'confirmed';
            return http.Response('{"items":{}}', 200);
          }
          return http.Response(
              jsonEncode(request.url.path == '/healthz'
                  ? {
                      'status': 'ok',
                      'service': 'gerenciador-horas-edesk',
                      'busy': false
                    }
                  : {
                      'items': [
                        {'key': 'a' * 64, 'state': state}
                      ]
                    }),
              200);
        });
  });
  tearDown(() {
    EdeskIntegrationApi.clientFactory = originalFactory;
    EdeskIntegrationApi.tokenProvider = originalToken;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
            body: FilledButton(
                onPressed: () => reviewEdeskSend(data, 'edesk_horas.py'),
                child: const Text('Abrir')))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'new send releases unconfirmed attempts without an extra checkbox',
      (tester) async {
    state = 'uncertain';
    await open(tester);
    FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar e enviar'));
    expect(find.textContaining('Não confirmado na tentativa anterior'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(button().onPressed, isNotNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'manual confirmation blocks repeat sending and preserves per-hour choice',
      (tester) async {
    state = 'uncertain';
    await open(tester);
    await tester.ensureVisible(find.text('Esta hora já está registrada'));
    await tester.tap(find.text('Esta hora já está registrada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sim, já estão registradas'));
    await tester.pumpAndSettle();
    expect(find.text('Já confirmado — não será reenviado'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmar e enviar'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('previous hours can be confirmed without being resent',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Esta hora já está registrada'));
    await tester.tap(find.text('Esta hora já está registrada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sim, já estão registradas'));
    await tester.pumpAndSettle();
    expect(find.text('Já confirmado — não será reenviado'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('review and backup dialogs fit a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showBackupDialog(context),
                    child: const Text('Backup'))))));
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();
    expect(find.text('Backup e restauração'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
  });

  testWidgets('connection indicator shows actual service health',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EdeskConnectionButton())));
    await tester.pumpAndSettle();
    expect(find.byTooltip('E-Desk conectado e pronto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
