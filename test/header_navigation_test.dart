import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';

void main() {
  for (final width in [
    900.0,
    1024.0,
    1150.0,
    1280.0,
    1366.0,
    1400.0,
    1536.0,
    1920.0
  ]) {
    for (final scale in [1.0, 1.25]) {
      testWidgets(
          'Todas as abas acessíveis sem sobrepor pesquisa: $width, escala $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        UserCache()
          ..carregado = true
          ..userName = 'Usuário de conferência';
        addTearDown(() => UserCache().limparCache());
        var selected = -1;
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                appBar: Cabecalho(
                    selectedIndex: 0,
                    onSelectTab: (index) => selected = index,
                    searchQuery: '',
                    onSearchChanged: (_) {},
                    userName: 'Usuário'))));
        await tester.pumpAndSettle();
        final request = find.byTooltip('Solicitações');
        expect(request, findsOneWidget);
        if (width >= 980) {
          expect(find.text('Usuário de conferência').hitTestable(), findsOneWidget);
        }
        final requestRect = tester.getRect(request);
        final searchRect = tester.getRect(find.byType(TextField));
        expect(requestRect.right, lessThanOrEqualTo(searchRect.left));
        expect(requestRect.width, greaterThanOrEqualTo(36));
        for (final label in [
          'Projetos',
          'Cadastro de Trabalhos',
          'Métricas',
          'Projetos Finalizados',
          'Orientações',
          'Tarefas',
          'Check List',
          'Solicitações'
        ]) {
          expect(find.byTooltip(label).hitTestable(), findsOneWidget);
        }
        await tester.tap(request);
        expect(selected, 7);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
