import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:math' as math;
import '../../../domain/models/monthly_hours.dart';
import 'package:flutter/material.dart';

class DailyHoursPoint {
  final String label;
  final double hours;
  final DateTime? date;
  final bool isWeekend;
  final bool isHighlighted;
  const DailyHoursPoint(
      {required this.label,
      required this.hours,
      this.date,
      this.isWeekend = false,
      this.isHighlighted = false});
}

class GraficoHorasWidget extends StatelessWidget {
  final MonthlyHours? monthly;
  final double monthlyWorked;
  final List<DailyHoursPoint> points;
  final String Function(double) formatHours;
  final ValueChanged<DateTime>? onDayTap;
  const GraficoHorasWidget(
      {super.key,
      required this.points,
      required this.formatHours,
      this.onDayTap,
      this.monthly,
      this.monthlyWorked = 0});
  static Color get cyan => AppPalette.accent;
  static Color get green => AppPalette.success;
  static Color get muted => AppPalette.secondary;

  Widget _label(String value,
          {double size = 10, Color? color, bool bold = false}) =>
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: size,
              height: 1.2,
              color: color ?? muted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final weekEnd =
        DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
    final total = points.fold(0.0, (sum, point) => sum + point.hours);
    final week = points
        .where((point) =>
            point.date != null &&
            !point.date!.isBefore(weekStart) &&
            point.date!.isBefore(weekEnd))
        .fold(0.0, (sum, point) => sum + point.hours);
    final peak =
        points.fold(0.0, (value, point) => math.max(value, point.hours));
    final scale = math.max(1.0, peak.ceilToDouble());

    Widget summary(String name, double value, Color color) => Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(name),
          const SizedBox(height: 2),
          _label(formatHours(value),
              size: 18, color: color ?? muted, bold: true)
        ]));

    return Container(
        padding: AppVisuals.cardPadding,
        decoration: AppVisuals.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            AppAppearance.watch(context);
            final title = Row(children: [
              Icon(Icons.bar_chart, color: cyan, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: _label('Evolução de horas',
                      size: 13, color: AppPalette.text, bold: true)),
            ]);
            final values = monthly;
            if (values == null)
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    _label('Últimos ${points.length} dias'),
                    const SizedBox(height: 9)
                  ]);
            Widget value(String label, double hours, Color color) => Expanded(
                child: Tooltip(
                    message: '$label: ${formatHours(hours)}',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(label, size: 8),
                          const SizedBox(height: 3),
                          _label(formatHours(hours),
                              size: 14, color: color ?? muted, bold: true)
                        ])));
            final indicators =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(
                  '${values.month.month.toString().padLeft(2, '0')}/${values.month.year} • Meta mensal',
                  size: 8),
              const SizedBox(height: 4),
              Row(children: [
                value('Previstas', values.planned, AppPalette.text),
                value('Meta cobrada', values.goal, cyan),
                value('Cobradas', values.charged, green),
                value('Faltam', values.remaining, AppPalette.warning)
              ]),
            ]);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (constraints.maxWidth >= 490)
                    Row(children: [
                      SizedBox(
                          width: 150,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                _label('Últimos ${points.length} dias', size: 8)
                              ])),
                      const SizedBox(width: 10),
                      Expanded(child: indicators)
                    ])
                  else ...[title, const SizedBox(height: 5), indicators],
                  const SizedBox(height: 6),
                  Tooltip(
                      message:
                          '${(values.goal > 0 ? values.charged / values.goal * 100 : 0).round()}% da meta cobrada • somente Hs Cobradas',
                      child: LinearProgressIndicator(
                          value: values.progress,
                          minHeight: 3,
                          color: green,
                          backgroundColor: AppPalette.surface)),
                  const SizedBox(height: 6),
                ]);
          }),
          Row(children: [
            summary('Trabalhadas no m\u00eas', monthlyWorked, cyan),
            summary('Semana', week, green)
          ]),
          const SizedBox(height: 9),
          Expanded(
              child: points.isEmpty
                  ? Center(child: _label('Nenhum apontamento no período'))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          SizedBox(
                              width: 31,
                              child: Padding(
                                  padding: const EdgeInsets.only(
                                      top: 16, bottom: 19),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _label(formatHours(scale), size: 8),
                                        _label(formatHours(scale / 2), size: 8),
                                        _label('00:00', size: 8)
                                      ]))),
                          Expanded(
                              child: Stack(children: [
                            Positioned.fill(
                                top: 16,
                                bottom: 19,
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: List.generate(
                                        3,
                                        (index) => Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: AppPalette.surface)))),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: points
                                    .map((point) => Expanded(
                                        child: Tooltip(
                                            message:
                                                '${point.label}: ${formatHours(point.hours)}\nClique para ver os apontamentos',
                                            child: InkWell(
                                                onTap: point.date == null ||
                                                        onDayTap == null
                                                    ? null
                                                    : () =>
                                                        onDayTap!(point.date!),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 2),
                                                    child: Column(children: [
                                                      SizedBox(
                                                          height: 16,
                                                          child: _label(
                                                              formatHours(
                                                                  point.hours),
                                                              size: 9,
                                                              color: point
                                                                      .isHighlighted
                                                                  ? green
                                                                  : cyan)),
                                                      Expanded(child:
                                                          LayoutBuilder(builder:
                                                              (context,
                                                                  constraints) {
                                                        AppAppearance.watch(
                                                            context);
                                                        return Align(
                                                            alignment: Alignment
                                                                .bottomCenter,
                                                            child: Container(
                                                                width: math.min(
                                                                    25.0,
                                                                    constraints
                                                                            .maxWidth *
                                                                        0.65),
                                                                height: point
                                                                            .hours <=
                                                                        0
                                                                    ? 4
                                                                    : math.max(
                                                                        4.0,
                                                                        constraints.maxHeight *
                                                                            (point.hours / scale).clamp(0.0,
                                                                                1.0)),
                                                                decoration: BoxDecoration(
                                                                    color: point.hours <= 0
                                                                        ? muted
                                                                        : point.isHighlighted
                                                                            ? green
                                                                            : cyan,
                                                                    borderRadius: BorderRadius.circular(3))));
                                                      })),
                                                      const SizedBox(height: 5),
                                                      SizedBox(
                                                          height: 14,
                                                          child: _label(
                                                              point.label,
                                                              size: 9)),
                                                    ]))))))
                                    .toList()),
                          ])),
                        ])),
          const SizedBox(height: 7),
          _label(
              total == 0
                  ? 'Sem horas registradas no período · clique em um dia'
                  : 'Clique em um dia para ver os apontamentos',
              size: 9),
        ]));
  }
}
