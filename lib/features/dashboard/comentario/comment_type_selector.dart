import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Keeps the two common types visible while preserving legacy template types.
class CommentTypeSelector extends StatelessWidget {
  const CommentTypeSelector({super.key, required this.value, this.onChanged});
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TIPO DE COMENTÁRIO',
            style: TextStyle(
                color: AppPalette.secondary,
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(
            height: 42,
            child: Row(children: [
              for (final type in const ['Interno', 'Externo'])
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: OutlinedButton(
                            onPressed: onChanged == null
                                ? null
                                : () => onChanged!(type),
                            style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                backgroundColor: value == type
                                    ? AppPalette.field
                                    : AppPalette.surface,
                                foregroundColor: value == type
                                    ? AppPalette.accent
                                    : AppPalette.secondary,
                                side: BorderSide(
                                    color: value == type
                                        ? AppPalette.accent
                                        : AppPalette.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: Text(type,
                                style: const TextStyle(fontSize: 11))))),
              PopupMenuButton<String>(
                  tooltip: value.startsWith('Padrão') ? value : 'Outros tipos',
                  enabled: onChanged != null,
                  onSelected: onChanged,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  itemBuilder: (_) => [
                        for (final type in const ['Padrão', 'Padrão (Interno)'])
                          CheckedPopupMenuItem(
                              value: type,
                              checked: value == type,
                              child: Text(type))
                      ]),
            ])),
      ],
    );
  }
}
