import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class ProgressoProjetoWidget extends StatelessWidget {
  final ProjectModel activeProject;
  final List<TimeLog> timeLogs;
  final double Function(String) parseTimeToHours;
  final String Function(double) formatHours;
  final String Function(DateTime) formatDateShort;
  const ProgressoProjetoWidget(
      {super.key,
      required this.activeProject,
      required this.timeLogs,
      required this.parseTimeToHours,
      required this.formatHours,
      required this.formatDateShort});
  static Color get cyan => AppPalette.accent;
  static Color get green => AppPalette.success;
  static Color get muted => AppPalette.secondary;

  double _executed(String target) => timeLogs
      .where((log) => log.targetId == target)
      .fold(0.0, (sum, log) => sum + WorkDuration.minutes(log) / 60);

  double get _projectExecuted {
    final targets = (activeProject.subTasks ?? [])
        .map((task) => '${activeProject.id}_${task.subId}')
        .toSet();
    return timeLogs
        .where((log) =>
            targets.contains(log.targetId) ||
            log.targetId == activeProject.id ||
            log.projectId == activeProject.id)
        .fold(0.0, (sum, log) => sum + WorkDuration.minutes(log) / 60);
  }

  Widget _text(String value,
          {Color? color,
          double size = 11,
          bool bold = false,
          TextAlign align = TextAlign.left}) =>
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
              color: color ?? AppPalette.text,
              fontSize: size,
              height: 1.2,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

  Widget _progress(double planned, double actual) {
    final ratio = planned > 0 ? (actual / planned).clamp(0.0, 1.0) : 0.0;
    return Row(children: [
      Expanded(
          child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  color: cyan,
                  backgroundColor: AppPalette.surface))),
      const SizedBox(width: 5),
      SizedBox(
          width: 31,
          child: _text('${(ratio * 100).round()}%',
              size: 9, color: muted, align: TextAlign.right)),
    ]);
  }

  Widget _metric(String label, double hours, Color color) => Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            _text(label, color: muted, size: 10),
            const SizedBox(height: 3),
            _text(formatHours(hours),
                color: color ?? AppPalette.text, size: 16, bold: true),
          ]));

  Widget _tableRow(
          {required Widget name,
          required Widget progress,
          required Widget planned,
          required Widget actual,
          required Widget remaining}) =>
      Row(children: [
        Expanded(flex: 34, child: name),
        const SizedBox(width: 7),
        Expanded(flex: 24, child: progress),
        const SizedBox(width: 7),
        Expanded(flex: 14, child: planned),
        const SizedBox(width: 5),
        Expanded(flex: 14, child: actual),
        const SizedBox(width: 5),
        Expanded(flex: 14, child: remaining),
      ]);

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final planned = parseTimeToHours(activeProject.estimatedHours);
    final actual = _projectExecuted;
    final tasks = activeProject.subTasks ?? [];
    return Container(
        padding: AppVisuals.cardPadding,
        decoration: AppVisuals.card,
        child: LayoutBuilder(builder: (context, constraints) {
          AppAppearance.watch(context);
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                  width:
                      constraints.maxWidth < 480 ? 480 : constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.work_outline, size: 18, color: cyan),
                          const SizedBox(width: 6),
                          Expanded(
                              child: _text('Projeto selecionado',
                                  size: 13, bold: true))
                        ]),
                        const SizedBox(height: 4),
                        Tooltip(
                            message:
                                '${activeProject.id} · ${activeProject.client}',
                            child: _text(
                                '${activeProject.id} · ${activeProject.client}',
                                bold: true,
                                size: 12)),
                        const SizedBox(height: 2),
                        _text(
                            '${activeProject.serviceType} · ${formatDateShort(activeProject.startDate)}',
                            size: 10,
                            color: muted),
                        const SizedBox(height: 7),
                        Container(
                            height: 43,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                                color: AppPalette.field,
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Expanded(
                                  flex: 2,
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _text('Total do projeto',
                                            size: 10, color: muted),
                                        const SizedBox(height: 5),
                                        _progress(planned, actual)
                                      ])),
                              const SizedBox(width: 12),
                              _metric('Previsto', planned, AppPalette.text),
                              _metric('Realizado', actual, cyan),
                              _metric(
                                  'Restante',
                                  (planned - actual)
                                      .clamp(0.0, double.infinity),
                                  green)
                            ])),
                        const SizedBox(height: 7),
                        _text('Etapas do projeto (${tasks.length})',
                            size: 11, bold: true),
                        const SizedBox(height: 3),
                        SizedBox(
                            height: 20,
                            child: _tableRow(
                                name: _text('Etapa', color: muted, size: 10),
                                progress:
                                    _text('Progresso', color: muted, size: 10),
                                planned: _text('Previsto',
                                    color: muted,
                                    size: 10,
                                    align: TextAlign.right),
                                actual: _text('Realizado',
                                    color: muted,
                                    size: 10,
                                    align: TextAlign.right),
                                remaining: _text('Restante',
                                    color: muted,
                                    size: 10,
                                    align: TextAlign.right))),
                        Expanded(
                            child: tasks.isEmpty
                                ? Center(
                                    child: _text('Nenhuma etapa cadastrada',
                                        color: muted))
                                : ListView.builder(
                                    padding: EdgeInsets.zero,
                                    primary: false,
                                    itemCount: tasks.length,
                                    itemExtent: 23,
                                    itemBuilder: (context, index) {
                                      final task = tasks[index];
                                      final estimate =
                                          parseTimeToHours(task.estimatedHours);
                                      final done = _executed(
                                          '${activeProject.id}_${task.subId}');
                                      final left = (estimate - done)
                                          .clamp(0.0, double.infinity);
                                      return Container(
                                          decoration: const BoxDecoration(
                                              border: Border(
                                                  top: BorderSide(
                                                      color:
                                                          Color(0xFF233245)))),
                                          child: Tooltip(
                                              message:
                                                  '${task.stage}\nPrevisto: ${formatHours(estimate)} · '
                                                  'Realizado: ${formatHours(done)} · Restante: ${formatHours(left)}',
                                              child: _tableRow(
                                                  name: _text(task.stage,
                                                      size: 10),
                                                  progress:
                                                      _progress(estimate, done),
                                                  planned: _text(
                                                      formatHours(estimate),
                                                      size: 10,
                                                      align: TextAlign.right),
                                                  actual: _text(
                                                      formatHours(done),
                                                      size: 10,
                                                      color: cyan,
                                                      align: TextAlign.right),
                                                  remaining: _text(
                                                      formatHours(left),
                                                      size: 10,
                                                      color: left == 0
                                                          ? muted
                                                          : green,
                                                      align:
                                                          TextAlign.right))));
                                    }))
                      ])));
        }));
  }
}
