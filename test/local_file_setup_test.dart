import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/native_local_files_service.dart';
import 'package:gerenciador_horas/features/projects/widgets/local_file_setup_dialog.dart';

void main() {
  testWidgets('missing local service offers setup instead of retrying an open', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showLocalFileError(context,
        const NativeFilesException('Integração indisponível', code: 'connection'), resource: 'a pasta'),
        child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir arquivos neste computador'), findsOneWidget);
    expect(find.text('Abrir configuração').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalFileSetupDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an authentication failure does not tell the user to install the integration', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showLocalFileError(context,
        const NativeFilesException('Entre novamente na sua conta.'), resource: 'a planilha'),
        child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar'), findsNothing);
    expect(find.textContaining('Entre novamente'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
