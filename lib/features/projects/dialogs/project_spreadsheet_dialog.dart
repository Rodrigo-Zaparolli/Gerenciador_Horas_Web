import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/native_local_files_service.dart';
import '../../../domain/models/project_model.dart';

class ProjectSpreadsheetDialog extends StatefulWidget {
  const ProjectSpreadsheetDialog({super.key, required this.project,
    this.uidProvider, this.emailProvider, this.transport});
  final ProjectModel project;
  final String? Function()? uidProvider, emailProvider;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;

  static Future<void> show(BuildContext context, ProjectModel project) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) return;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProjectSpreadsheetDialog(project: project));
  }

  @override
  State<ProjectSpreadsheetDialog> createState() =>
      _ProjectSpreadsheetDialogState();
}

class _ProjectSpreadsheetDialogState extends State<ProjectSpreadsheetDialog> {
  final Map<String, Map<String, dynamic>> pending = {};
  Map<String, dynamic>? data;
  String? error, notice, owner;
  bool busy = false;
  String search = '', filter = 'Todas';
  StreamSubscription<User?>? subscription;
  String? get uid => widget.uidProvider != null ? widget.uidProvider!() : FirebaseAuth.instance.currentUser?.uid;
  String? get email => widget.emailProvider != null ? widget.emailProvider!() : FirebaseAuth.instance.currentUser?.email;
  bool get authorized {
    return uid == owner && PilotFeatureAccess.allows(uid: uid, email: email);
  }

  Future<Map<String, dynamic>> request(String action, {String? revision, List<Map<String, dynamic>>? changes}) {
    if (widget.transport != null) return widget.transport!({'action': action,
      'reference': widget.project.excelLink, if (revision != null) 'revision': revision, if (changes != null) 'changes': changes});
    return NativeLocalFiles.call(action, reference: widget.project.excelLink, revision: revision, changes: changes);
  }

  @override
  void initState() {
    super.initState();
    owner = uid;
    if (widget.uidProvider == null) subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted && !authorized) {
        setState(() {
          data = null;
          pending.clear();
          error = 'A conta mudou. Feche esta janela e entre novamente.';
        });
      }
    });
    load();
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<bool> discard() async =>
      pending.isEmpty ||
      await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                      title: const Text('Descartar alterações?'),
                      content: const Text(
                          'As alterações ainda não foram salvas na planilha.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Continuar editando')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Descartar'))
                      ])) ==
          true;

  Future<void> load() async {
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await request('excel-editor-read');
      if (mounted && authorized)
        setState(() {
          data = result;
          pending.clear();
          notice = null;
        });
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!authorized || busy || pending.isEmpty || data == null) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final result = await request('excel-editor-write',
          revision: data!['revision'] as String,
          changes: pending.values.toList());
      if (result['saved'] != true)
        throw StateError(
            'A gravação não foi confirmada. Recarregue para conferir antes de tentar novamente.');
      if (mounted && authorized)
        setState(() {
          data = result;
          pending.clear();
          notice =
              'Planilha atualizada e conferida. Backup: ${result['backup']}';
        });
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String keyOf(Map<String, dynamic> field) =>
      '${field['sheet']}!${field['cell']}';
  dynamic current(Map<String, dynamic> field) =>
      pending[keyOf(field)]?['value'] ?? field['value'];
  void change(Map<String, dynamic> field, dynamic value) => setState(() {
        final key = keyOf(field);
        if (value == field['value']) {
          pending.remove(key);
        } else {
          pending[key] = {
            'sheet': field['sheet'],
            'cell': field['cell'],
            'before': field['value'],
            'value': value
          };
        }
        notice = null;
      });

  Future<void> close() async {
    if (busy || !await discard() || !mounted) return;
    pending.clear();
    Navigator.pop(context);
  }

  Widget input(Map<String, dynamic> field) {
    final label = field['label'] as String;
    final kind = field['kind'];
    if (kind == 'yesno')
      return DropdownButtonFormField<String>(
          key: ValueKey('${data!['revision']}:${keyOf(field)}'),
          initialValue: current(field) as String,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: 'Sim', child: Text('Sim')),
            DropdownMenuItem(value: 'Não', child: Text('Não'))
          ],
          onChanged: busy ? null : (v) => change(field, v));
    if (kind == 'date') {
      final raw = current(field) as String;
      final date = DateTime.tryParse(raw);
      final text = date == null
          ? raw
          : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      return TextFormField(
          key: ValueKey('${data!['revision']}:${keyOf(field)}:$raw'),
          initialValue: text,
          readOnly: true,
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: IconButton(
                  tooltip: 'Limpar data',
                  onPressed: busy ? null : () => change(field, ''),
                  icon: const Icon(Icons.clear, size: 16))),
          onTap: busy
              ? null
              : () async {
                  final selected = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200));
                  if (selected != null && mounted && authorized)
                    change(field, selected.toIso8601String().substring(0, 10));
                });
    }
    return TextFormField(
        key: ValueKey('${data!['revision']}:${keyOf(field)}'),
        initialValue: current(field).toString(),
      enabled: !busy && authorized,
      readOnly: field['readOnly'] == true,
        obscureText: label.toLowerCase().contains('senha'),
      decoration: InputDecoration(labelText: label, helperText: field['readOnly'] == true ? 'Calculado pelo Excel' : null),
        maxLength: 10000,
        buildCounter: (_,
                {required currentLength, required isFocused, maxLength}) =>
            null,
        onChanged: (v) => change(field, v));
  }

  Widget entry() {
    final fields = (data!['fields'] as List).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Padding(padding: EdgeInsets.only(bottom: 12), child: Text(
        'Alterar os produtos não executa o botão “Atualizar Planilha de Implantação”. Use esse botão no Excel quando necessário.')),
      for (final group in fields.map((f) => f['group'] as String).toSet())
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth < 620
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 32) / 3;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 14),
                        Wrap(spacing: 16, runSpacing: 16, children: [
                          for (final field
                              in fields.where((f) => f['group'] == group))
                            SizedBox(width: width, child: input(field))
                        ])
                      ]);
                })))
    ]);
  }

  Widget checklist() {
    final all = (data!['tasks'] as List).cast<Map<String, dynamic>>();
    final shown = all
        .where((f) =>
            (f['label'] as String)
                .toLowerCase()
                .contains(search.toLowerCase()) &&
            (filter == 'Todas' ||
                filter == 'Concluídas' && current(f) == 1 ||
                filter == 'Pendentes' && current(f) != 1))
        .toList();
    final progress = data!['progress'];
    return Column(children: [
      if (progress is num)
        Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Progresso do projeto: ${(progress * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.toDouble()),
              const SizedBox(height: 4),
              const Text(
                  'Calculado pelo Excel na última leitura; atualizado após salvar.',
                  style: TextStyle(fontSize: 11))
            ])),
      Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 12, runSpacing: 8, children: [
            SizedBox(
                width: 260,
                child: TextField(
                    decoration: const InputDecoration(
                        hintText: 'Buscar tarefa...',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => search = v))),
            for (final item in ['Todas', 'Pendentes', 'Concluídas'])
              ChoiceChip(
                  label: Text(item),
                  selected: filter == item,
                  onSelected: (_) => setState(() => filter = item))
          ])),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
            for (final group in all.map((f) => f['group'] as String).toSet())
              Card(
                  child: ExpansionTile(
                      title: Text(group),
                      subtitle: Text(
                          '${shown.where((f) => f['group'] == group).length} tarefas neste filtro'),
                      children: [
                    for (final task in shown.where((f) => f['group'] == group))
                      ListTile(
                          title: Text(task['label'] as String),
                          subtitle: Text(
                              'Estimado: ${task['estimated']}${task['note'] == '' ? '' : '\n${task['note']}'}'),
                          trailing: SizedBox(
                              width: 85,
                              child: DropdownButton<double>(
                                  isExpanded: true,
                                  value: const [
                                    0.0,
                                    .25,
                                    .5,
                                    .75,
                                    1.0
                                  ].contains((current(task) as num).toDouble())
                                      ? (current(task) as num).toDouble()
                                      : null,
                                  hint: Text(
                                      '${((current(task) as num) * 100).round()}%'),
                                  items: [
                                    for (final v in [0.0, .25, .5, .75, 1.0])
                                      DropdownMenuItem(
                                          value: v,
                                          child: Text('${(v * 100).round()}%'))
                                  ],
                                  onChanged: busy || !authorized
                                      ? null
                                      : (v) {
                                          if (v != null) change(task, v);
                                        })))
                  ]))
          ]))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return PopScope(
        canPop: !busy && pending.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) close();
        },
        child: Dialog(
            insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
            child: SizedBox(
                width: 1150,
                height: size.height * .9,
                child: DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      ListTile(
                          title: const Text('Planilha do projeto'),
                          subtitle: Text(
                              '${widget.project.id} · ${data?['filename'] ?? widget.project.client}'),
                          trailing: IconButton(
                              onPressed: busy ? null : close,
                              icon: const Icon(Icons.close))),
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      if (notice != null)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(notice!)),
                      const TabBar(tabs: [
                        Tab(text: 'Informações de entrada'),
                        Tab(text: 'Checklist-Processo')
                      ]),
                      Expanded(
                          child: data == null || !authorized
                              ? Center(
                                  child: Text(busy
                                      ? 'Carregando a planilha...'
                                      : 'Nenhuma planilha carregada.'))
                              : TabBarView(children: [entry(), checklist()])),
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(pending.isEmpty
                                    ? 'Sem alterações pendentes'
                                    : '${pending.length} alteração(ões) não salva(s)'),
                                OutlinedButton(
                                    onPressed:
                                        busy || !authorized ? null : load,
                                    child: const Text('Recarregar do Excel')),
                                TextButton(
                                    onPressed: busy ? null : close,
                                    child: const Text('Cancelar')),
                                FilledButton.icon(
                                    onPressed:
                                        busy || !authorized || pending.isEmpty
                                            ? null
                                            : save,
                                    icon: const Icon(Icons.save_outlined),
                                    label: const Text('Salvar na planilha'))
                              ]))
                    ])))));
  }
}
