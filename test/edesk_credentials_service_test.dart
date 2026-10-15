import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final fixture = {'email': 'consultor@example.test', 'senha': 'fixture only ã! '};
  test('save waits for cloud acknowledgment and restores on a fresh computer', () async {
    String? uid = 'credentials-cloud';
    Map<String, dynamic>? cloud;
    final ack = Completer<void>();
    var finished = false;
    final first = EdeskCredentialsService(uidProvider: () => uid,
      writeRemote: (owner, data) async { await ack.future; cloud = Map.of(data); },
      readRemote: (_) async => cloud);
    final saving = first.salvar(email: ' ${fixture['email']} ', senha: fixture['senha']!)
      .then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    ack.complete();
    await saving;
    expect(cloud, fixture);
    expect(await first.ler(), fixture);
    uid = null;
    expect(await first.ler(), isNull);
    FlutterSecureStorage.setMockInitialValues({});
    uid = 'credentials-cloud';
    var reads = 0;
    final second = EdeskCredentialsService(uidProvider: () => uid,
      readRemote: (_) async { reads++; return cloud; });
    expect(await second.ler(), fixture);
    expect(reads, 1);
    final secure = const FlutterSecureStorage();
    expect(jsonDecode((await secure.read(key: 'edesk_credentials_v2_credentials-cloud'))!), fixture);
  });
  test('failed cloud save never reports success or replaces local data', () async {
    final service = EdeskCredentialsService(uidProvider: () => 'credentials-failure',
      writeRemote: (_, __) async => throw StateError('offline'));
    await expectLater(service.salvar(email: fixture['email']!, senha: fixture['senha']!), throwsStateError);
    expect(await const FlutterSecureStorage().read(key: 'edesk_credentials_v2_credentials-failure'), isNull);
  });
  test('offline fallback uses only the current account and ignores unscoped legacy keys', () async {
    String? uid = 'credentials-offline';
    FlutterSecureStorage.setMockInitialValues({
      'edesk_credentials_v2_credentials-offline': jsonEncode(fixture),
      'edesk_email': 'legacy@example.test', 'edesk_password': 'legacy-fixture',
    });
    final service = EdeskCredentialsService(uidProvider: () => uid,
      readRemote: (_) async => throw StateError('offline'));
    expect(await service.ler(), fixture);
    uid = 'credentials-other';
    await expectLater(service.ler(), throwsStateError);
    uid = null;
    expect(await service.ler(), isNull);
  });
  test('account switch during a cloud read never returns the other account password', () async {
    String? uid = 'credentials-switch-a';
    final pending = Completer<Map<String, dynamic>?>();
    final service = EdeskCredentialsService(uidProvider: () => uid, readRemote: (_) => pending.future);
    final reading = service.ler();
    uid = 'credentials-switch-b';
    pending.complete(fixture);
    await expectLater(reading, throwsStateError);
    expect(await const FlutterSecureStorage().read(key: 'edesk_credentials_v2_credentials-switch-b'), isNull);
  });
  test('simultaneous credential requests share one cloud read and return copies', () async {
    final pending = Completer<Map<String, dynamic>?>();
    var reads = 0;
    final service = EdeskCredentialsService(uidProvider: () => 'credentials-concurrent',
      readRemote: (_) { reads++; return pending.future; });
    final first = service.ler(), second = service.ler();
    pending.complete(fixture);
    final data = await first;
    data!['senha'] = 'changed copy';
    expect(await second, fixture);
    expect(reads, 1);
  });
  test('remove deletes cloud and account-specific local credentials', () async {
    Map<String, dynamic>? cloud = fixture;
    final service = EdeskCredentialsService(uidProvider: () => 'credentials-remove',
      readRemote: (_) async => cloud, deleteRemote: (_) async => cloud = null);
    expect(await service.ler(), fixture);
    await service.apagar();
    expect(cloud, isNull);
    expect(await service.ler(), isNull);
    expect(await const FlutterSecureStorage().read(key: 'edesk_credentials_v2_credentials-remove'), isNull);
  });
  test('cloud deletion on another computer clears a stale local copy', () async {
    FlutterSecureStorage.setMockInitialValues({
      'edesk_credentials_v2_credentials-deleted': jsonEncode(fixture),
    });
    final service = EdeskCredentialsService(uidProvider: () => 'credentials-deleted',
      readRemote: (_) async => null);
    expect(await service.ler(), isNull);
    expect(await const FlutterSecureStorage().read(key: 'edesk_credentials_v2_credentials-deleted'), isNull);
  });
  test('a slow old read cannot undo newly acknowledged credentials', () async {
    final pending = Completer<Map<String, dynamic>?>();
    final service = EdeskCredentialsService(uidProvider: () => 'credentials-slow-read',
      readRemote: (_) => pending.future, writeRemote: (_, __) async {});
    final reading = service.ler();
    await service.salvar(email: fixture['email']!, senha: fixture['senha']!);
    pending.complete({'email': 'old@example.test', 'senha': 'old fixture'});
    expect(await reading, fixture);
    expect(await service.ler(), fixture);
  });
}
