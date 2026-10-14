import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/controle_projetos_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/progresso_projeto_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/grafico_horas_widget.dart';
import 'dashboard_cards_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CAPTURE_APPEARANCE'] == '1') {
      final font = File(r'C:\Windows\Fonts\segoeui.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Segoe UI');
        loader.addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  for (final mode in AppVisualTheme.values) {
    for (final width in [1024.0, 1440.0]) {
      testWidgets('cards compactos preservam ações em $mode / $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = mode;
        addTearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
        UserCache().carregado = true;
        UserCache().userName = 'Teste';
        addTearDown(UserCache().limparCache);
        final imageKey = GlobalKey();
        var created = 0;
        final controls = ControleProjetosWidget(
          agrupar: false,
          ordenarPrioridade: false,
          somenteAtivos: false,
          filtroAtivo: false,
          tipoServicoSelecionado: 'Todos os Serviços',
          tiposServicoOpcoes: const ['Consultoria'],
          onNewProject: () => created++,
          onSynchronize: () {},
          onFilter: () {},
          onManual: () {},
          onStart: () {},
          onPause: () {},
          onStop: () {},
          onAgruparChanged: (_) {},
          onOrdenarPrioridadeChanged: (_) {},
          onSomenteAtivosChanged: (_) {},
          onTipoServicoChanged: (_) {},
          onDataInicioChanged: (_) {},
          onDataFimChanged: (_) {},
          filtroProjetos: '',
          onFiltroProjetosChanged: (_) => null,
        );
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode.mode,
          home: RepaintBoundary(
              key: imageKey,
              child: Scaffold(
                  appBar: Cabecalho(
                      selectedIndex: 0,
                      onSelectTab: (_) {},
                      searchQuery: '',
                      onSearchChanged: (_) {},
                      userName: 'Teste'),
                  body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                          height: 260,
                          child: Row(children: [
                            Expanded(flex: 3, child: controls),
                            const SizedBox(width: 12),
                            Expanded(
                                flex: 4,
                                child: ProgressoProjetoWidget(
                                    activeProject: fixture.project([
                                      fixture.task('2', '08:00'),
                                      fixture.task('3', '09:00')
                                    ]),
                                    timeLogs: [
                                      fixture.log('a', '100_2', '04:30')
                                    ],
                                    parseTimeToHours: fixture.parseHours,
                                    formatHours: fixture.formatHours,
                                    formatDateShort: (_) => '09/10/2026')),
                            const SizedBox(width: 12),
                            Expanded(
                                flex: 4,
                                child: GraficoHorasWidget(
                                    points: const [
                                      DailyHoursPoint(
                                          label: '09/10', hours: 4.5)
                                    ],
                                    formatHours: fixture.formatHours,
                                    monthlyWorked: 4.5)),
                          ]))))),
        ));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Novo trabalho'));
        expect(created, 1);
        await tester.pump(const Duration(milliseconds: 300));
        if (Platform.environment['CAPTURE_APPEARANCE'] == '1') {
          await tester.runAsync(() async {
            final boundary = imageKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/visual-polish/${mode.preference}-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
