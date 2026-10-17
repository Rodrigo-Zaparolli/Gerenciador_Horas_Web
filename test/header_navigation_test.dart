import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/shared/widgets/adaptive_header_navigation.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';

void main() {
  testWidgets(
      'Usa nomes completos, depois reduzidos, e setas só quando necessário',
      (tester) async {
    final labels = List.generate(8, (i) => 'Nome completo aba $i');
    final short = List.generate(8, (i) => 'Aba $i');
    tester.view.physicalSize = const Size(2100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final layout in [
      (2000.0, false, false),
      (600.0, true, false),
      (300.0, true, true)
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: layout.$1,
                      height: 68,
                      child: AdaptiveHeaderNavigation(
                          labels: labels,
                          shortLabels: short,
                          itemBuilder: (i, compact) => Tooltip(
                              message: labels[i],
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 6 : 10),
                                  child: Text(compact ? short[i] : labels[i],
                                      style: TextStyle(
                                          fontSize:
                                              compact ? 10.5 : 11))))))))));
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        expect(find.text(layout.$2 ? short[i] : labels[i]), findsOneWidget);
      }
      expect(find.byTooltip('Próximas abas'),
          layout.$3 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
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
        expect(find.text('Solicitações').hitTestable(), findsOneWidget);
        if (width >= 980) {
          expect(find.text('Usuário de conferência').hitTestable(),
              findsOneWidget);
        }
        final requestRect = tester.getRect(request);
        final searchRect = tester.getRect(find.byType(TextField));
        expect(requestRect.right, lessThanOrEqualTo(searchRect.left));
        expect(requestRect.width, greaterThanOrEqualTo(36));
        if (find.byTooltip('Próximas abas').evaluate().isNotEmpty) {
          final position = tester
              .state<ScrollableState>(find.descendant(
                  of: find.byType(AdaptiveHeaderNavigation),
                  matching: find.byType(Scrollable)))
              .position;
          await tester.tap(find.byTooltip('Próximas abas'));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          await tester.tap(find.byTooltip('Abas anteriores'));
          await tester.pumpAndSettle();
          expect(position.pixels, 0);
        }
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
          final text = find.descendant(
              of: find.byTooltip(label), matching: find.byType(Text));
          expect(text, findsOneWidget);
          final short = switch (label) {
            'Cadastro de Trabalhos' => 'Trabalhos',
            'Projetos Finalizados' => 'Finalizados',
            'Check List' => 'Checklist',
            _ => label,
          };
          expect(tester.widget<Text>(text).data, anyOf(label, short));
          await Scrollable.ensureVisible(tester.element(text), alignment: .5);
          await tester.pumpAndSettle();
          expect(text.hitTestable(), findsOneWidget);
        }
        await tester.tap(request);
        expect(selected, 7);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
