import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

class WorkHourWidget extends StatelessWidget {
  final Map<String, double> hoursData;
  final String Function(double) formatHours;

  const WorkHourWidget({
    super.key,
    required this.hoursData,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    // Caso não haja dados, exibe um estado vazio elegante
    if (hoursData.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.text.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(
            'Nenhum registro de tempo encontrado',
            style: TextStyle(color: AppPalette.secondary, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: hoursData.entries.map((entry) {
          final label = entry.key;
          final val = entry.value;
          final heightPct = (val / 10.0).clamp(0.05, 1.0);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                formatHours(val),
                style: TextStyle(color: AppPalette.secondary, fontSize: 8),
              ),
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 80 * heightPct,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: AppPalette.secondary, fontSize: 8),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
