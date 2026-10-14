import '../../../core/theme/app_palette.dart';
import 'package:flutter/material.dart';

List<int> edeskPhaseIndices(int total, Set<int> selected, {required bool all}) {
  if (total <= 0) {
    throw StateError('Este projeto não possui fases para enviar.');
  }
  if (all) return List<int>.generate(total, (index) => index);
  if (selected.isEmpty) {
    throw StateError('Selecione ao menos uma fase para enviar.');
  }
  if (selected.any((index) => index < 0 || index >= total)) {
    throw StateError('A lista de fases mudou. Selecione as fases novamente.');
  }
  return selected.toList()..sort();
}

class EdeskPhaseSendButton extends StatelessWidget {
  const EdeskPhaseSendButton(
      {super.key,
      required this.total,
      required this.selectedCount,
      required this.busy,
      required this.onSend,
      this.enabled = true});
  final int total;
  final int selectedCount;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onSend;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final buttonColor = AppPalette.readableText(primary,
      background: Color.alphaBlend(primary.withValues(alpha: 0.15), Theme.of(context).colorScheme.surface));
    return PopupMenuButton<bool>(
        tooltip: 'Escolher quais fases enviar ao E-Desk',
        enabled: enabled && !busy && total > 0,
        onSelected: onSend,
        itemBuilder: (_) => [
          PopupMenuItem(
              value: true, child: Text('Enviar todas as fases ($total)')),
          PopupMenuItem(
              value: false,
              enabled: selectedCount > 0,
              child: Text('Enviar selecionadas ($selectedCount)')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: buttonColor.withValues(alpha: busy ? 0.08 : 0.15),
              border:
                  Border.all(color: buttonColor.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.sync, size: 18, color: buttonColor),
            const SizedBox(width: 8),
            Text(busy ? 'Atualizando E-Desk...' : 'Enviar fases ao E-Desk',
                style: TextStyle(
                    color: buttonColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (!busy)
              Icon(Icons.arrow_drop_down, color: buttonColor),
          ]),
        ),
      );
  }
}
