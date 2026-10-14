import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/data/services/edesk_operation_history.dart';
import 'package:gerenciador_horas/data/services/web_release_monitor.dart';

void main() {
  setUp(() {
    LocalUserState.memory = {};
    EdeskOperationHistory.clearSession();
    EdeskActivity.active = 0;
  });
  tearDown(() {
    LocalUserState.memory = null;
  });
  List<dynamic> queued(String uid) =>
      LocalUserState.read(uid, EdeskOperationHistory.outboxFeature)?['items']
          as List? ??
      [];
  String begin(String uid) =>
      EdeskOperationHistory.begin(uid, '/api/edesk/horas', {'enviar': true})!;

  test(
      'failed metadata sync survives session restart and never resends a delivery',
      () async {
    final id = begin('a');
    EdeskOperationHistory.update('a', id, 'confirmed');
    await EdeskOperationHistory.flush('a',
        isCurrentAccount: () => true,
        writer: (_) async => throw Exception('offline'));
    EdeskOperationHistory.clearSession();
    expect(queued('a').single['state'], 'confirmed');
    final writes = <Map<String, dynamic>>[];
    await EdeskOperationHistory.flush('a',
        isCurrentAccount: () => true,
        writer: (row) async {
          writes.add(row);
        });
    expect(writes.single['id'], id);
    expect(writes.single.containsKey('request'), isFalse);
    expect(queued('a'), isEmpty);
    expect(EdeskOperationHistory.read('a').single['state'], 'confirmed');
  });
  test('account change blocks queued sync', () async {
    begin('a');
    var calls = 0;
    await EdeskOperationHistory.flush('a',
        isCurrentAccount: () => false,
        writer: (_) async {
          calls++;
        });
    expect(calls, 0);
    expect(queued('a'), hasLength(1));
    expect(queued('b'), isEmpty);
  });
  test(
      'new confirmation during pending write remains queued and concurrent flush is serialized',
      () async {
    final id = begin('a');
    final gate = Completer<void>();
    var calls = 0;
    final first = EdeskOperationHistory.flush('a',
        isCurrentAccount: () => true,
        writer: (_) async {
          calls++;
          await gate.future;
        });
    await Future<void>.delayed(Duration.zero);
    EdeskOperationHistory.update('a', id, 'confirmed');
    await EdeskOperationHistory.flush('a',
        isCurrentAccount: () => true,
        writer: (_) async {
          calls++;
        });
    gate.complete();
    await first;
    expect(calls, 1);
    expect(queued('a').single['state'], 'confirmed');
    await EdeskOperationHistory.flush('a',
        isCurrentAccount: () => true,
        writer: (row) async {
          expect(row['state'], 'confirmed');
        });
    expect(queued('a'), isEmpty);
  });
  test('activity lock releases even after an error', () async {
    await expectLater(EdeskActivity.track(() async {
      expect(EdeskActivity.active, 1);
      throw Exception('failure');
    }), throwsException);
    expect(EdeskActivity.active, 0);
  });

  test('conflict resolution protects confirmations even with clock differences',
      () {
    expect(
        EdeskOperationHistory.shouldReplace(
            {'state': 'confirmed', 'updated': '2020-01-01T00:00:00Z'},
            {'state': 'pending', 'updated': '2099-01-01T00:00:00Z'}),
        isFalse);
    expect(
        EdeskOperationHistory.shouldReplace(
            {'state': 'uncertain', 'updated': '2099-01-01T00:00:00Z'},
            {'state': 'confirmed', 'updated': '2020-01-01T00:00:00Z'}),
        isTrue);
  });

  test(
      'conflict resolution preserves newer unconfirmed outcomes and accepts first writes',
      () {
    expect(
        EdeskOperationHistory.shouldReplace(
            {'state': 'uncertain', 'updated': '2026-10-12T12:01:00Z'},
            {'state': 'pending', 'created': '2026-10-12T12:00:00Z'}),
        isFalse);
    expect(
        EdeskOperationHistory.shouldReplace(
            null, {'state': 'pending', 'created': '2026-10-12T12:00:00Z'}),
        isTrue);
  });

  Future<void> mount(WidgetTester tester,
          {required Future<String?> Function() loader,
          VoidCallback? reload,
          Widget? child}) =>
      tester.pumpWidget(MaterialApp(
          home: WebReleaseMonitor(
              installedRelease: 'installed',
              releaseLoader: loader,
              synchronize: () {},
              reload: reload,
              child: child ?? const Scaffold(body: Text('App')))));

  testWidgets('shows release changes before updating on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: WebReleaseMonitor(
      installedRelease: 'old',
      releaseLoader: () async => 'new',
      notesLoader: () async => ['Gr?fico di?rio de horas.', 'Meta mensal.'],
      synchronize: () {},
      child: const Scaffold(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('O que mudou nesta vers?o:'), findsOneWidget);
    expect(find.text('? Gr?fico di?rio de horas.'), findsOneWidget);
    expect(find.text('? Meta mensal.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Depois'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('asks before reloading and reloads only with explicit click',
      (tester) async {
    var reloads = 0;
    await mount(tester,
        loader: () async => 'new',
        reload: () {
          reloads++;
        });
    await tester.pumpAndSettle();
    expect(find.text('Nova versão disponível'), findsOneWidget);
    expect(reloads, 0);
    await tester.tap(find.text('Atualizar app'));
    await tester.pumpAndSettle();
    expect(reloads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('waits for an ongoing send before checking for updates',
      (tester) async {
    EdeskActivity.active = 1;
    var checks = 0;
    await mount(tester, loader: () async {
      checks++;
      return 'new';
    });
    await tester.pumpAndSettle();
    expect(checks, 0);
    EdeskActivity.active = 0;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Nova versão disponível'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a send starting during version request prevents the popup',
      (tester) async {
    final response = Completer<String?>();
    await mount(tester, loader: () => response.future);
    EdeskActivity.active = 1;
    response.complete('new');
    await tester.pumpAndSettle();
    expect(find.text('Nova versão disponível'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('same version and network failure do not interrupt work',
      (tester) async {
    await mount(tester, loader: () async => 'installed');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, loader: () async => throw Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Later dismisses notification for this release without reloading',
      (tester) async {
    var reloads = 0;
    await mount(tester,
        loader: () async => 'new',
        reload: () {
          reloads++;
        });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Depois'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 6));
    await tester.pumpAndSettle();
    expect(find.text('Nova versão disponível'), findsNothing);
    expect(reloads, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an open modal prevents the update notice until it is closed',
      (tester) async {
    final response = Completer<String?>();
    await mount(tester,
        loader: () => response.future,
        child: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            const AlertDialog(title: Text('Editor aberto'))),
                    child: const Text('Abrir editor')))));
    await tester.tap(find.text('Abrir editor'));
    await tester.pumpAndSettle();
    response.complete('new');
    await tester.pumpAndSettle();
    expect(find.text('Nova versão disponível'), findsNothing);
    expect(find.text('Editor aberto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
