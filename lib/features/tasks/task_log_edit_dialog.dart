import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';
import 'task_time_picker.dart';

class TaskLogEditDialog extends StatefulWidget {
  const TaskLogEditDialog({super.key, required this.log, required this.save});
  final TimeLog log;
  final Future<void> Function(TimeLog) save;
  @override
  State<TaskLogEditDialog> createState() => _TaskLogEditDialogState();
}

class _TaskLogEditDialogState extends State<TaskLogEditDialog> {
  final form = GlobalKey<FormState>();
  late final task = TextEditingController(text: widget.log.taskName ?? '');
  late final description = TextEditingController(text: widget.log.description ?? '');
  late final start = TextEditingController(text: widget.log.startTime);
  late final end = TextEditingController(text: widget.log.endTime);
  bool saving = false;
  String? error;

  @override
  void dispose() {
    for (final controller in [task, description, start, end]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> pick(TextEditingController controller) async {
    final minutes = WorkDuration.clock(controller.text) ?? 480;
    final selected = await showTaskTimePicker(context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    if (!mounted || saving || selected == null) return;
    setState(() => controller.text = WorkDuration.format(selected.hour * 60 + selected.minute));
  }

  Future<void> submit() async {
    if (saving || !form.currentState!.validate()) return;
    final minutes = WorkDuration.clock(end.text)! - WorkDuration.clock(start.text)!;
    final original = widget.log;
    final updated = TimeLog(id: original.id, targetId: original.targetId,
      date: original.date, startTime: WorkDuration.format(WorkDuration.clock(start.text)!),
      endTime: WorkDuration.format(WorkDuration.clock(end.text)!),
      durationFormatted: WorkDuration.format(minutes), durationMinutes: minutes,
      hours: minutes / 60, isRegistered: original.isRegistered,
      projectId: original.projectId, projectName: original.projectName,
      taskName: task.text, description: description.text, typeHs: original.typeHs);
    setState(() { saving = true; error = null; });
    try {
      await widget.save(updated).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() => saving = false);
      Navigator.of(context).pop();
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = failure is TimeoutException
            ? 'O salvamento ainda não foi confirmado. Confira a conexão e o registro antes de tentar novamente. Suas alterações continuam aqui.'
            : '${recoveryError(failure, operation: 'salvar o apontamento')} Suas alterações continuam aqui.';
      });
    }
  }

  Widget timeField(String label, TextEditingController controller) => TextFormField(
    controller: controller, enabled: !saving, keyboardType: TextInputType.datetime,
    decoration: InputDecoration(labelText: label, hintText: 'HH:MM',
      suffixIcon: IconButton(tooltip: 'Selecionar $label', onPressed: saving ? null : () => pick(controller),
        icon: const Icon(Icons.schedule))),
    validator: (value) {
      final clock = WorkDuration.clock(value ?? '');
      if (clock == null) return 'Informe HH:MM válido.';
      if (controller == end) {
        final first = WorkDuration.clock(start.text);
        if (first != null && clock <= first) return 'Término deve ser após o início.';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Editar Apontamento'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: task, enabled: !saving, decoration: const InputDecoration(labelText: 'Nome da Tarefa')),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: timeField('Início', start)), const SizedBox(width: 12),
            Expanded(child: timeField('Término', end)),
          ]),
          const SizedBox(height: 16),
          TextFormField(controller: description, enabled: !saving, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrição / Descritivo')),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])))),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: saving ? null : submit,
          child: Text(saving ? 'Salvando…' : 'Salvar')),
      ],
    ),
  );
}
