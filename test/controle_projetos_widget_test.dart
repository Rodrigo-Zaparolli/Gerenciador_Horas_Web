import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/controle_projetos_widget.dart';

void main() {
  testWidgets(
      'limpar remove serviço e ambas as datas; todos não filtra por nome',
      (tester) async {
    String? service = 'Consultoria';
    DateTime? start = DateTime(2026, 10, 8);
    DateTime? end = DateTime(2026, 10, 9);
    var filters = 0;
    var created = 0;
    var synchronized = 0;
    final expanded = <String>{'projeto'};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 225,
          height: 260,
          child: ControleProjetosWidget(
            agrupar: false,
            ordenarPrioridade: false,
            somenteAtivos: false,
            filtroAtivo: true,
            tipoServicoSelecionado: service,
            tiposServicoOpcoes: const ['Consultoria', 'Consultoria'],
            dataInicio: start,
            dataFim: end,
            expandedProjectIds: expanded,
            onNewProject: () => created++,
            onSynchronize: () => synchronized++,
            onFilter: () => filters++,
            onManual: () {},
            onStart: () {},
            onPause: () {},
            onStop: () {},
            onAgruparChanged: (value) {},
            onOrdenarPrioridadeChanged: (value) {},
            onSomenteAtivosChanged: (value) {},
            onTipoServicoChanged: (value) => service = value,
            onDataInicioChanged: (value) => start = value,
            onDataFimChanged: (value) => end = value,
            filtroProjetos: '',
            onFiltroProjetosChanged: (value) => null,
          )),
    ))));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Limpar filtros'));
    await tester.pump();
    expect(service, isNull);
    expect(start, isNull);
    expect(end, isNull);
    expect(filters, 1);
    final dropdown = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    dropdown.onChanged!('Consultoria');
    await tester.pump();
    expect(service, 'Consultoria');
    dropdown.onChanged!('Todos os Serviços');
    await tester.pump();
    expect(service, isNull);
    await tester.tap(find.text('Novo trabalho'));
    await tester.tap(find.byTooltip('Sincronizar'));
    expect(created, 1);
    expect(synchronized, 1);
    expect(expanded, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
