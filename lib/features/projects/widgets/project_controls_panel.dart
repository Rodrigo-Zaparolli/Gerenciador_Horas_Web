import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

class ProjectControlsPanel extends StatelessWidget {
  final bool agrupar;
  final ValueChanged<bool?> onAgruparChanged;

  final bool ordenarPrioridade;
  final ValueChanged<bool?> onOrdenarPrioridadeChanged;

  final bool onlyActive;
  final ValueChanged<bool?> onOnlyActiveChanged;

  final VoidCallback onNewProjectPressed;
  final VoidCallback onSyncPressed;
  final VoidCallback onFilterPressed;
  final VoidCallback onManualPressed;
  final VoidCallback onStartPressed;
  final VoidCallback onPausePressed;
  final VoidCallback onStopPressed;

  final bool hasFilterActive;

  const ProjectControlsPanel({
    super.key,
    required this.agrupar,
    required this.onAgruparChanged,
    required this.ordenarPrioridade,
    required this.onOrdenarPrioridadeChanged,
    required this.onlyActive,
    required this.onOnlyActiveChanged,
    required this.onNewProjectPressed,
    required this.onSyncPressed,
    required this.onFilterPressed,
    required this.onManualPressed,
    required this.onStartPressed,
    required this.onPausePressed,
    required this.onStopPressed,
    required this.hasFilterActive,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCheckboxOption(
              'Agrupar',
              agrupar,
              onAgruparChanged,
            ),
            _buildCheckboxOption(
              'Ordenar por prioridade',
              ordenarPrioridade,
              onOrdenarPrioridadeChanged,
            ),
            _buildCheckboxOption(
              'Somente Proj. Ativos',
              onlyActive,
              onOnlyActiveChanged,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.surface,
                  foregroundColor: AppPalette.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add, size: 15, color: Colors.cyanAccent),
                label: const Text(
                  'Novo Projeto',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onNewProjectPressed,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickAction(
                  Icons.sync,
                  'Sincronizar',
                  Colors.cyanAccent,
                  onSyncPressed,
                ),
                _buildQuickAction(
                  hasFilterActive
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  'Filtrar',
                  hasFilterActive ? Colors.orangeAccent : Colors.cyanAccent,
                  onFilterPressed,
                ),
                _buildQuickAction(
                  Icons.timer_outlined,
                  'Manual',
                  Colors.tealAccent,
                  onManualPressed,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickAction(
                  Icons.play_arrow,
                  'Iniciar',
                  Colors.greenAccent,
                  onStartPressed,
                ),
                _buildQuickAction(
                  Icons.pause,
                  'Pausar',
                  Colors.amberAccent,
                  onPausePressed,
                ),
                _buildQuickAction(
                  Icons.check_circle_outline,
                  'Stop',
                  Colors.redAccent,
                  onStopPressed,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxOption(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.cyanAccent,
              checkColor: AppPalette.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: AppPalette.secondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
