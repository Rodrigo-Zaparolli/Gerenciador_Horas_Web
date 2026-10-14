import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';

class ChecklistModelDialog extends StatelessWidget {
  final ChecklistFormat? format;
  final Function(ChecklistFormat) onSave;

  const ChecklistModelDialog({
    super.key,
    this.format,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
