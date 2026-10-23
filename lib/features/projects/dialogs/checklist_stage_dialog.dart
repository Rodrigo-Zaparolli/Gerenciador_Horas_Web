import 'package:flutter/material.dart';

class ChecklistStageDialog extends StatefulWidget {
  const ChecklistStageDialog(
      {super.key,
      required this.stage,
      required this.tasks,
      required this.values,
      required this.canApply});
  final String stage;
  final List<Map<String, dynamic>> tasks;
  final Map<String, double> values;
  final bool Function() canApply;
  static String fieldKey(Map<String, dynamic> task) =>
      '${task['sheet']}!${task['cell']}';
  @override
  State<ChecklistStageDialog> createState() => _ChecklistStageDialogState();
}

class _ChecklistStageDialogState extends State<ChecklistStageDialog> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _controllers = <String, TextEditingController>{};
  final _initialText = <String, String>{};
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final task in widget.tasks) {
      final key = ChecklistStageDialog.fieldKey(task);
      final percent = (widget.values[key] ?? 0) * 100;
      _controllers[key] = TextEditingController(
          text: percent == percent.roundToDouble()
              ? percent.toInt().toString()
              : percent.toStringAsFixed(2));
      _initialText[key] = _controllers[key]!.text;
    }
  }

  double? percent(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));
  String? validate(String key, String raw) {
    if (raw == _initialText[key]) return null;
    final value = percent(raw);
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      return 'Use 0 a 100';
    }
    return const [0, 25, 50, 75, 100].contains(value)
        ? null
        : 'Use 0, 25, 50, 75 ou 100';
  }

  void apply() {
    if (!widget.canApply()) {
      Navigator.pop(context);
      return;
    }
    _form.currentState!.validate();
    for (final task in widget.tasks) {
      final key = ChecklistStageDialog.fieldKey(task);
      if (validate(key, _controllers[key]!.text) != null) {
        setState(() => _error = 'Confira o percentual de ${task['label']}.');
        return;
      }
    }
    Navigator.pop(context, <String, double>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text == _initialText[entry.key]
            ? widget.values[entry.key]!
            : percent(entry.value.text)! / 100
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(widget.stage),
      content: SizedBox(
          width: 820,
          height: (MediaQuery.sizeOf(context).height * .60).clamp(160.0, 570.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                '${widget.tasks.length} tarefas · Percentuais do checklist: 0%, 25%, 50%, 75% ou 100%.'),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: colors.error))),
            Expanded(
                child: Form(
                    key: _form,
                    child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView(controller: _scroll, children: [
                          for (final task in widget.tasks)
                            Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    task['label']?.toString() ??
                                                        '',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                Text(
                                                    'Estimado: ${task['estimated'] ?? '—'}',
                                                    style: TextStyle(
                                                        color: colors
                                                            .onSurfaceVariant)),
                                                if ((task['note']?.toString() ??
                                                        '')
                                                    .isNotEmpty)
                                                  Text(task['note'].toString(),
                                                      style: TextStyle(
                                                          color: colors
                                                              .onSurfaceVariant)),
                                              ])),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                              width: 100,
                                              child: TextFormField(
                                                key: ValueKey(
                                                    'stage-percent-${ChecklistStageDialog.fieldKey(task)}'),
                                                controller: _controllers[
                                                    ChecklistStageDialog
                                                        .fieldKey(task)],
                                                readOnly:
                                                    task['readOnly'] == true,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration: const InputDecoration(
                                                    labelText: 'Realizado',
                                                    suffixText: '%',
                                                    border:
                                                        OutlineInputBorder()),
                                                validator: (raw) => validate(
                                                    ChecklistStageDialog
                                                        .fieldKey(task),
                                                    raw ?? ''),
                                              )),
                                        ]))),
                        ])))),
            const SizedBox(height: 12),
            const Text(
                'Aplicar ajustes atualiza o editor e a prévia do Status Projeto. Para gravar no Excel, use Salvar na planilha.'),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton.icon(
            onPressed: apply,
            icon: const Icon(Icons.check),
            label: const Text('Aplicar ajustes')),
      ],
    );
  }
}
