import 'package:flutter/material.dart';
import '../../../data/services/edesk_service.dart';
import '../../../domain/models/project_model.dart';
import 'comment_percentage.dart';

class StandalonePercentageDialog extends StatefulWidget {
  const StandalonePercentageDialog(
      {super.key,
      required this.tasks,
      required this.initialValue,
      required this.canSend,
      required this.onSend});
  final List<TaskModel> tasks;
  final String initialValue;
  final bool Function() canSend;
  final Future<EdeskSendResult> Function(TaskModel, double) onSend;
  @override
  State<StandalonePercentageDialog> createState() =>
      _StandalonePercentageDialogState();
}

class _StandalonePercentageDialogState
    extends State<StandalonePercentageDialog> {
  final form = GlobalKey<FormState>();
  late final value = TextEditingController(text: widget.initialValue);
  late final tasks = widget.tasks
      .where((task) => task.edeskWorkNumber.isNotEmpty)
      .toList();
  TaskModel? selected;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    selected = tasks.isEmpty ? null : tasks.first;
  }

  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || selected == null || !form.currentState!.validate()) return;
    if (!widget.canSend()) {
      setState(() => error = 'A conta mudou. Feche e abra novamente.');
      return;
    }
    final percentage = parseCommentPercentage(value.text)!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.onSend(selected!, percentage);
      if (!mounted) return;
      if (!widget.canSend()) {
        setState(() =>
            error = 'A conta mudou. Confira o resultado antes de repetir.');
      } else if (result.confirmed) {
        Navigator.pop(context, percentage);
      } else if (result.statusCode != 499) {
        setState(() => error = result.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Não foi possível confirmar a porcentagem. Confira o E-Desk antes de repetir.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Atualizar somente a porcentagem'),
        content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Abre o trabalho e salva o campo % Realizado. O comentário e seus prints não serão enviados.'),
                          const SizedBox(height: 16),
                          if (tasks.isEmpty)
                            const Text(
                                'Nenhum trabalho com ID E-Desk configurado neste projeto.')
                          else
                            DropdownButtonFormField<TaskModel>(
                                initialValue: selected,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Trabalho no E-Desk'),
                                items: [
                                  for (final task in tasks)
                                    DropdownMenuItem(
                                        value: task,
                                        child: Text(
                                            '${task.stage} · ${task.edeskWorkNumber}',
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: busy
                                    ? null
                                    : (task) =>
                                        setState(() => selected = task)),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: value,
                              enabled: !busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: '% Realizado', suffixText: '%'),
                              validator: (text) {
                                try {
                                  return parseCommentPercentage(text ?? '') ==
                                          null
                                      ? 'Informe a porcentagem.'
                                      : null;
                                } on FormatException catch (failure) {
                                  return failure.message;
                                }
                              }),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                        ])))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: busy || tasks.isEmpty ? null : send,
              child: Text(busy ? 'Atualizando…' : 'Conferir e enviar')),
        ],
      ));
}
