import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/integration_downloads.dart';
import 'package:gerenciador_horas/data/services/web_release_monitor.dart';

Map<String, dynamic> metadata(String version) => {
      'version': version,
      'updateUrl': '/downloads/atualizacao-integracao-completa-$version.zip',
      'completeUrl':
          '/downloads/integracao-edesk-completa-windows-v$version.zip',
    };

void main() {
  test('download metadata follows current and future native versions', () {
    for (final version in ['49', '50', '105']) {
      final parsed = IntegrationDownloads.fromJson(metadata(version));
      expect(parsed?.version, version);
      expect(parsed?.updatePath, metadata(version)['updateUrl']);
      expect(parsed?.completePath, metadata(version)['completeUrl']);
    }
    expect(IntegrationDownloads.fromJson(null), isNull);
    for (final invalid in [
      'https://other.example/file-49.zip',
      '//other.example/file-49.zip',
      '/downloads/../file-49.zip',
      '/downloads/file-48.zip',
      'javascript:alert(1)',
      '/downloads/file-49.zip?version=49'
    ]) {
      expect(
          IntegrationDownloads.fromJson(
              {...metadata('49'), 'updateUrl': invalid}),
          isNull);
    }
  });

  for (final version in ['49', '50']) {
    testWidgets(
        'release modal downloads integration v$version without reload or dismissal',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final links = <Uri>[];
      var reloads = 0;
      var fail = true;
      await tester.pumpWidget(MaterialApp(
          home: WebReleaseMonitor(
        installedRelease: 'old',
        releaseLoader: () async => 'new',
        notesLoader: () async => ['Melhoria na planilha.'],
        integrationLoader: () async =>
            IntegrationDownloads.fromJson(metadata(version)),
        openIntegrationDownload: (uri) async {
          links.add(uri);
          return !fail;
        },
        synchronize: () {},
        reload: () {
          reloads++;
        },
        child: const Scaffold(body: Text('App')),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Integração E-Desk v$version'), findsOneWidget);
      final update = find.byKey(const ValueKey('download-integration-update'));
      await tester.ensureVisible(update);
      await tester.tap(update);
      await tester.pumpAndSettle();
      expect(links.single.path, metadata(version)['updateUrl']);
      expect(find.textContaining('Não foi possível iniciar o download'),
          findsOneWidget);
      expect(find.text('Nova versão disponível'), findsOneWidget);
      expect(reloads, 0);
      fail = false;
      final complete =
          find.byKey(const ValueKey('download-integration-complete'));
      await tester.ensureVisible(complete);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(links.last.path, metadata(version)['completeUrl']);
      expect(find.text('Nova versão disponível'), findsOneWidget);
      expect(reloads, 0);
      await tester.tap(find.text('Atualizar app'));
      await tester.pumpAndSettle();
      expect(reloads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
