import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_endpoint.dart';

void main() {
  test(
      'endereço central exige HTTPS ou IPv4 privado e nunca aceita credenciais na URL',
      () {
    for (final value in [
      'http://10.0.0.2:8765',
      'http://172.31.2.2:8765',
      'http://192.168.0.10:8765',
      'https://example.com/backend/',
      'http://127.0.0.1:8765'
    ]) {
      expect(normalizeEdeskUrl(value), isNotEmpty);
    }
    for (final value in [
      'http://example.com',
      'http://8.8.8.8',
      'http://172.32.1.1',
      'http://192.168.999.1',
      'https://user:password@example.com',
      'https://example.com?token=secret',
      'https://example.com/#secret',
      'file:///tmp'
    ]) {
      expect(() => normalizeEdeskUrl(value), throwsFormatException);
    }
  });
  test(
      'configuração acompanha a conta e não reaproveita endereço de outro usuário',
      () async {
    String? uid = 'one';
    final records = <String, Map<String, dynamic>>{
      'one': {'mode': 'central', 'url': 'http://192.168.1.10:8765'},
    };
    final settings = EdeskEndpointSettings(
        uidProvider: () => uid,
        read: (owner) async => records[owner],
        write: (owner, value) async => records[owner] = value);
    expect(await settings.currentUrl(), 'http://192.168.1.10:8765');
    uid = 'two';
    expect(await settings.currentUrl(), defaultEdeskApiUrl);
    await settings.save(centralUrl: 'https://example.com/backend/');
    expect(records['two']?['url'], 'https://example.com/backend');
    uid = 'one';
    expect(await settings.currentUrl(), 'http://192.168.1.10:8765');
    uid = null;
    expect(await settings.currentUrl(), defaultEdeskApiUrl);
  });
  test('falha na nuvem não troca silenciosamente para outra integração',
      () async {
    final settings = EdeskEndpointSettings(
        uidProvider: () => 'one',
        read: (_) async => throw StateError('offline'));
    await expectLater(settings.currentUrl(), throwsStateError);
  });
  test('simultaneous startup and progress requests share one configuration read', () async {
    final pending = Completer<Map<String, dynamic>?>();
    var reads = 0;
    final settings = EdeskEndpointSettings(
      uidProvider: () => 'one',
      read: (_) { reads++; return pending.future; },
    );
    final first = settings.currentUrl();
    final second = settings.currentUrl();
    pending.complete({'mode': 'local'});
    expect(await first, defaultEdeskApiUrl);
    expect(await second, defaultEdeskApiUrl);
    expect(reads, 1);
    expect(await settings.currentUrl(), defaultEdeskApiUrl);
    expect(reads, 1);
  });
  test('explicit refresh still reads changes from another computer', () async {
    var reads = 0;
    final settings = EdeskEndpointSettings(
      uidProvider: () => 'one',
      read: (_) async => ++reads == 1 ? {'mode': 'local'} : {'mode': 'central', 'url': 'https://example.test'},
    );
    expect(await settings.currentUrl(), defaultEdeskApiUrl);
    expect(await settings.currentUrl(refresh: true), 'https://example.test');
    expect(reads, 2);
  });
  test('troca de conta durante leitura rejeita o resultado antigo', () async {
    String? uid = 'one';
    final pending = Completer<Map<String, dynamic>?>();
    final settings = EdeskEndpointSettings(
        uidProvider: () => uid, read: (_) => pending.future);
    final result = settings.currentUrl();
    uid = 'two';
    pending.complete({'mode': 'central', 'url': 'http://192.168.1.10:8765'});
    await expectLater(result, throwsStateError);
  });
}
