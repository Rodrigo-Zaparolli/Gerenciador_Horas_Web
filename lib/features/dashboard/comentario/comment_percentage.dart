import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

double? parseCommentPercentage(String text) {
  if (text.trim().isEmpty) return null;
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value < 0 || value > 100) {
    throw const FormatException('Informe um percentual entre 0 e 100.');
  }
  if ((value * 100 - (value * 100).round()).abs() > 0.000001) {
    throw const FormatException(
        'Use no m\u00e1ximo duas casas decimais no percentual.');
  }
  return value;
}

class CommentPercentageField extends StatelessWidget {
  const CommentPercentageField(
      {super.key, required this.controller, required this.enabled});
  final TextEditingController controller;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Tooltip(
        message:
            'Percentual realizado no E-Desk. Use Enviar só % para atualizar sem comentário. Deixe em branco para enviar somente o comentário.',
        child: Container(
            width: 184,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppPalette.border)),
            child: Row(children: [
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppPalette.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppPalette.border)),
                  child: Icon(Icons.donut_large_rounded,
                      color: AppPalette.accent, size: 17)),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('% Realizado',
                        maxLines: 1,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w600)),
                    SizedBox(
                        height: 21,
                        child: Semantics(
                            label: 'Percentual realizado',
                            child: TextField(
                                controller: controller,
                                enabled: enabled,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'))
                                ],
                                style: TextStyle(
                                    color: AppPalette.accent,
                                    fontSize: 12,
                                    height: 1.1,
                                    fontWeight: FontWeight.w600),
                                cursorColor: AppPalette.accent,
                                decoration: InputDecoration(
                                    hintText: 'Opcional: 0 a 100',
                                    hintStyle: TextStyle(
                                        color: AppPalette.secondary,
                                        fontSize: 9,
                                        height: 1.1,
                                        fontWeight: FontWeight.w400),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero))))
                  ])),
              const SizedBox(width: 6),
              Text('%',
                  style: TextStyle(
                      color: AppPalette.accent,
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.w700))
            ])));
  }
}
