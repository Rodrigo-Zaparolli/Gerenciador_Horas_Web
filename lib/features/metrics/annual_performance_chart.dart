import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/work_duration.dart';

class AnnualPerformanceChart extends StatelessWidget {
  const AnnualPerformanceChart(
      {super.key,
      required this.year,
      required this.totals,
      required this.goals,
      required this.selectedMonth,
      required this.color,
      required this.onMonthSelected});
  final int year, selectedMonth;
  final List<int> totals, goals;
  final Color color;
  final ValueChanged<int> onMonthSelected;
  static const months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez'
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Visão anual · $year',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Row(children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        const Text('Cobradas', style: TextStyle(fontSize: 10)),
        const SizedBox(width: 12),
        Text('-- Meta',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
      ]),
      const SizedBox(height: 8),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final maxMinutes = math.max(60, [...totals, ...goals].reduce(math.max));
        final maxHours = (maxMinutes / 60 / 40).ceil() * 40;
        return Row(children: [
          SizedBox(
              width: 30,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${maxHours}h', style: const TextStyle(fontSize: 9)),
                    Text('${maxHours ~/ 2}h',
                        style: const TextStyle(fontSize: 9)),
                    const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text('0h', style: TextStyle(fontSize: 9))),
                  ])),
          Expanded(
              child: Stack(children: [
            Positioned.fill(
                bottom: 20,
                child: CustomPaint(
                    painter: _AnnualPainter(
                        totals: totals,
                        goals: goals,
                        maxMinutes: maxHours * 60,
                        selected: selectedMonth - 1,
                        color: color,
                        grid: scheme.outlineVariant,
                        goalColor: scheme.onSurfaceVariant))),
            Row(
                children: List.generate(
                    12,
                    (i) => Expanded(
                            child: Tooltip(
                          message:
                              '${months[i]} $year\nCobradas: ${WorkDuration.format(totals[i])}\nMeta: ${WorkDuration.format(goals[i])}',
                          child: Semantics(
                            selected: selectedMonth == i + 1,
                            button: true,
                            child: InkWell(
                                key: ValueKey('annual-month-${i + 1}'),
                                onTap: () => onMonthSelected(i + 1),
                                child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(months[i],
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: selectedMonth == i + 1
                                                  ? FontWeight.w800
                                                  : FontWeight.w400,
                                              color: scheme.onSurface)),
                                    ))),
                          ),
                        )))),
          ])),
        ]);
      })),
    ]);
  }
}

class _AnnualPainter extends CustomPainter {
  _AnnualPainter(
      {required this.totals,
      required this.goals,
      required this.maxMinutes,
      required this.selected,
      required this.color,
      required this.grid,
      required this.goalColor});
  final List<int> totals, goals;
  final int maxMinutes, selected;
  final Color color, grid, goalColor;
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width / 12;
    double y(int value) => size.height * (1 - value / maxMinutes);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, size.height * fraction),
          Offset(size.width, size.height * fraction), gridPaint);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(selected * width, 0, width, size.height),
            const Radius.circular(4)),
        Paint()..color = color.withValues(alpha: 0.08));
    for (var i = 0; i < 12; i++) {
      if (totals[i] > 0)
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(i * width + width * 0.24, y(totals[i]),
                    (i + 1) * width - width * 0.24, size.height),
                const Radius.circular(2)),
            Paint()..color = color);
    }
    // A per-month target can vary; connect its actual values with a dashed line.
    final line = Paint()
      ..color = goalColor
      ..strokeWidth = 1.5;
    for (var i = 0; i < 11; i++) {
      final start = Offset((i + 0.5) * width, y(goals[i]));
      final end = Offset((i + 1.5) * width, y(goals[i + 1]));
      final distance = (end - start).distance;
      if (distance == 0) continue;
      for (double offset = 0; offset < distance; offset += 7) {
        canvas.drawLine(
            Offset.lerp(start, end, offset / distance)!,
            Offset.lerp(start, end, math.min(offset + 4, distance) / distance)!,
            line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnualPainter old) => true;
}
