import 'dart:async';
import 'spreadsheet_store.dart';
import 'company_contacts.dart';
import 'project_spreadsheet_kind.dart';
import 'checklist_status_preview.dart';
import 'checklist_live_preview.dart';
import 'spreadsheet_dialog_chrome.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/native_local_files_service.dart';
import '../../../domain/models/project_model.dart';

class ProjectSpreadsheetDialog extends StatefulWidget {
  const ProjectSpreadsheetDialog(
      {super.key,
      required this.project,
      this.uidProvider,
      this.emailProvider,
      this.transport,
      this.contactsLoader,
      this.store});
  final Future<List<CompanyContact>> Function()? contactsLoader;
  final SpreadsheetStore? store;
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
  final Map<String, String> calculatedEmails = {};
  Map<String, dynamic>? data;
  String? error, notice, owner;
  bool busy = false;
  late final ChecklistLivePreview livePreview;
  List<CompanyContact> contacts = [];
  SpreadsheetStore? get store =>
      widget.store ??
      (widget.transport == null ? FirebaseSpreadsheetStore() : null);
  String search = '', filter = 'Todas';
  StreamSubscription<User?>? subscription;
  String? get uid => widget.uidProvider != null
      ? widget.uidProvider!()
      : FirebaseAuth.instance.currentUser?.uid;
  String? get email => widget.emailProvider != null
      ? widget.emailProvider!()
      : FirebaseAuth.instance.currentUser?.email;
  bool get authorized {
    return uid == owner && PilotFeatureAccess.allows(uid: uid, email: email);
  }

  Future<Map<String, dynamic>> request(String action,
      {String? revision, List<Map<String, dynamic>>? changes}) {
    if (widget.transport != null)
      return widget.transport!({
        'action': action,
        'reference': widget.project.excelLink,
        'serviceType': widget.project.serviceType,
        if (revision != null) 'revision': revision,
        if (changes != null) 'changes': changes
      });
    return NativeLocalFiles.call(action,
        reference: widget.project.excelLink,
        serviceType: widget.project.serviceType,
        revision: revision,
        changes: changes);
  }

  @override
  void initState() {
    super.initState();
    owner = uid;
    livePreview = ChecklistLivePreview(calculate: calculateStatus);
    if (widget.uidProvider == null)
      subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted && !authorized) {
          livePreview.clear();
          setState(() {
            data = null;
            pending.clear();
            calculatedEmails.clear();
            error = 'A conta mudou. Feche esta janela e entre novamente.';
          });
        }
      });
    openSaved();
    if (widget.uidProvider == null || widget.contactsLoader != null)
      loadContacts();
  }

  @override
  void dispose() {
    subscription?.cancel();
    livePreview.dispose();
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

  Future<void> loadContacts() async {
    try {
      final result =
          await (widget.contactsLoader?.call() ?? CompanyContacts.load());
      if (mounted && authorized) setState(() => contacts = result);
    } catch (e) {
      if (mounted && authorized)
        setState(
            () => notice = 'Não foi possível carregar os colaboradores: $e');
    }
  }

  Future<void> openSaved() async {
    if (!authorized) return;
    setState(() => busy = true);
    String? warning;
    try {
      final saved = await store?.load(
          owner!, widget.project.id, widget.project.excelLink ?? '');
      if (!mounted || !authorized) return;
      if (saved != null &&
          spreadsheetMatchesProject(saved, widget.project.serviceType)) {
        setState(() {
          data = saved;
          busy = false;
        });
        return;
      }
    } catch (e) {
      warning = 'Não foi possível carregar a cópia salva: $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized) {
      await load();
      if (mounted && authorized && warning != null)
        setState(() => notice = warning);
    }
  }

  Future<void> remember(Map<String, dynamic> result) async {
    if (!authorized || store == null) return;
    final stamp = DateTime.now().toIso8601String();
    try {
      await store!.save(
          owner!, widget.project.id, widget.project.excelLink ?? '', result);
      if (mounted && authorized)
        setState(() => data = {...result, 'syncedAt': stamp});
    } catch (e) {
      if (mounted && authorized)
        setState(() => notice =
            'O Excel foi lido/gravado, mas a cópia no sistema não foi atualizada. Use Salvar cópia no sistema para tentar novamente. $e');
    }
  }

  String get synchronizationLabel {
    final date =
        DateTime.tryParse(data?['syncedAt']?.toString() ?? '')?.toLocal();
    if (date == null) return 'Cópia ainda não salva no sistema';
    return 'Última sincronização: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}. Atualize do Excel para buscar alterações externas.';
  }

  Future<void> load() async {
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final result = await request('excel-editor-read');
      if (!spreadsheetMatchesProject(result, widget.project.serviceType)) {
        throw StateError(
            'A integração retornou um checklist diferente do tipo do projeto. Atualize e reinicie a integração v25 para usar Professional/Maker.');
      }
      if (mounted && authorized)
        setState(() {
          data = result;
          pending.clear();
          calculatedEmails.clear();
          notice = null;
        });
      if (mounted && authorized) await remember(result);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) livePreview.resume(clear: true);
      }
    }
  }

  Future<Map<String, dynamic>> calculateStatus() async {
    if (!mounted || !authorized || data == null)
      throw StateError('A conta mudou.');
    final result = await request('excel-editor-preview',
        revision: data!['revision'] as String,
        changes: pending.values.toList());
    if (!mounted || !authorized) throw StateError('A conta mudou.');
    if (result['preview'] != true ||
        result['statusPreview'] is! Map ||
        !spreadsheetMatchesProject(result, widget.project.serviceType)) {
      throw StateError(
          'A integra\u00e7\u00e3o n\u00e3o confirmou a pr\u00e9via. Atualize e reinicie a integra\u00e7\u00e3o v29.');
    }
    return Map<String, dynamic>.from(result['statusPreview'] as Map);
  }

  Future<void> save() async {
    if (!authorized || busy || pending.isEmpty || data == null) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final result = await request('excel-editor-write',
          revision: data!['revision'] as String,
          changes: pending.values.toList());
      if (result['saved'] != true)
        throw StateError(
            'A gravação não foi confirmada. Recarregue para conferir antes de tentar novamente.');
      if (!spreadsheetMatchesProject(result, widget.project.serviceType)) {
        throw StateError(
            'O checklist retornado não corresponde ao projeto. Recarregue do Excel para conferir.');
      }
      final fields = (result['fields'] as List).cast<Map<String, dynamic>>();
      final differentEmails = calculatedEmails.entries
          .where((entry) => !fields.any((f) =>
              keyOf(f) == entry.key &&
              f['value'].toString().trim().toLowerCase() ==
                  entry.value.trim().toLowerCase()))
          .isNotEmpty;
      if (mounted && authorized)
        setState(() {
          data = result;
          pending.clear();
          calculatedEmails.clear();
          notice = differentEmails
              ? 'Planilha salva, mas a fórmula do Excel retornou um e-mail diferente do cadastro. Confira o cadastro de consultores no Excel; o e-mail mostrado agora é o resultado real da planilha. Backup: ${result['backup']}'
              : 'Planilha atualizada e conferida. Backup: ${result['backup']}';
          if (result['backupCleanupWarning'] != null) {
            notice = '$notice\n${result['backupCleanupWarning']}';
          }
        });
      if (mounted && authorized) await remember(result);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) livePreview.resume(clear: true);
      }
    }
  }

  String keyOf(Map<String, dynamic> field) =>
      '${field['sheet']}!${field['cell']}';
  dynamic current(Map<String, dynamic> field) =>
      pending[keyOf(field)]?['value'] ??
      calculatedEmails[keyOf(field)] ??
      field['value'];
  void change(Map<String, dynamic> field, dynamic value) => setState(() {
        final key = keyOf(field);
        if (field['label'].toString().endsWith('— Nome')) {
          for (final f
              in (data!['fields'] as List).cast<Map<String, dynamic>>()) {
            if (f['group'] == field['group'] &&
                f['label'] ==
                    field['label']
                        .toString()
                        .replaceFirst('— Nome', '— E-mail')) {
              calculatedEmails.remove(keyOf(f));
            }
          }
        }
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
        livePreview.invalidate();
      });

  Future<void> close() async {
    if (busy || !await discard() || !mounted) return;
    pending.clear();
    Navigator.pop(context);
  }

  Widget input(Map<String, dynamic> field) {
    final label = field['label'] as String;
    final kind = field['kind'];
    if (label.endsWith('— Nome') &&
        contacts.isNotEmpty &&
        field['readOnly'] != true) {
      return Autocomplete<CompanyContact>(
          key: ValueKey('${data!['revision']}:${keyOf(field)}'),
          initialValue: TextEditingValue(text: current(field).toString()),
          displayStringForOption: (c) => c.name,
          optionsBuilder: (text) => contacts.where((c) => '${c.name} ${c.email}'
              .toLowerCase()
              .contains(text.text.toLowerCase())),
          onSelected: (c) {
            if (busy || !authorized) return;
            change(field, c.name);
            final address = (data!['fields'] as List)
                .cast<Map<String, dynamic>>()
                .where((f) =>
                    f['group'] == field['group'] &&
                    f['label'] == label.replaceFirst('— Nome', '— E-mail'));
            if (address.isNotEmpty) {
              if (address.first['readOnly'] == true) {
                setState(
                    () => calculatedEmails[keyOf(address.first)] = c.email);
              } else {
                change(address.first, c.email);
              }
            }
          },
          optionsViewBuilder: (context, select, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                  elevation: 4,
                  child: SizedBox(
                      width: 340,
                      height: 220,
                      child: ListView(children: [
                        for (final c in options)
                          ListTile(
                              title: Text(c.name),
                              subtitle: Text(c.email),
                              onTap: () => select(c))
                      ])))),
          fieldViewBuilder: (context, controller, focus, submit) =>
              TextFormField(
                  controller: controller,
                  focusNode: focus,
                  enabled: !busy && authorized,
                  decoration: InputDecoration(labelText: label),
                  onFieldSubmitted: (_) => submit(),
                  onChanged: (v) => change(field, v)));
    }
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
        key: ValueKey(
            '${data!['revision']}:${keyOf(field)}:${field['label'].toString().endsWith('— E-mail') ? current(field) : ''}'),
        initialValue: current(field).toString(),
        enabled: !busy && authorized,
        readOnly: field['readOnly'] == true,
        obscureText: label.toLowerCase().contains('senha'),
        decoration: InputDecoration(
            labelText: label,
            helperText: calculatedEmails.containsKey(keyOf(field))
                ? 'E-mail do cadastro. A fórmula do Excel será conferida ao salvar.'
                : field['readOnly'] == true
                    ? 'Calculado pelo Excel'
                    : null),
        maxLength: 10000,
        buildCounter: (_,
                {required currentLength, required isFocused, maxLength}) =>
            null,
        onChanged: (v) => change(field, v));
  }

  Widget entry() {
    final fields = (data!['fields'] as List).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
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
    return LayoutBuilder(
        builder: (context, constraints) => Column(children: [
              SizedBox(
                  height: (constraints.maxHeight *
                          (constraints.maxHeight < 400 ? .42 : .52))
                      .clamp(80.0, 310.0),
                  child: ChecklistStatusPanel(
                      controller: livePreview, unsaved: pending.isNotEmpty)),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                                width: 260,
                                child: TextField(
                                    decoration: InputDecoration(
                                        hintText: 'Buscar tarefa...',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        prefixIcon: Icon(Icons.search)),
                                    onChanged: (v) =>
                                        setState(() => search = v))),
                            for (final item in [
                              'Todas',
                              'Pendentes',
                              'Concluídas'
                            ])
                              ChoiceChip(
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  label: Text(item),
                                  selected: filter == item,
                                  onSelected: (_) =>
                                      setState(() => filter = item)),
                            Text('${shown.length} tarefas',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]))),
              Expanded(
                  child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                    for (final group
                        in shown.map((f) => f['group'] as String).toSet())
                      Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant)),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              collapsedBackgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              title: Row(children: [
                                Expanded(
                                    child: Text(group,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .08),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text(
                                        '${shown.where((f) => f['group'] == group).length} tarefas',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall))
                              ]),
                              children: [
                                for (final task
                                    in shown.where((f) => f['group'] == group))
                                  ListTile(
                                      dense: true,
                                      minTileHeight: 58,
                                      shape: Border(
                                          top: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: .45))),
                                      leading:
                                          Icon(current(task) == 1 ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                                              size: 19,
                                              color: current(task) == 1
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                      title: Text(task['label'] as String,
                                          style: const TextStyle(fontSize: 14)),
                                      subtitle: Text(
                                          'Estimado: ${task['estimated']}${task['note'] == '' ? '' : '\n${task['note']}'}'),
                                      trailing: Container(
                                          width: 100,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          decoration: BoxDecoration(
                                              border:
                                                  Border.all(color: pending.containsKey(keyOf(task)) ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.outlineVariant),
                                              borderRadius: BorderRadius.circular(7)),
                                          child: DropdownButton<double>(
                                              isDense: true,
                                              underline: const SizedBox.shrink(),
                                              isExpanded: true,
                                              value: const [0.0, .25, .5, .75, 1.0].contains((current(task) as num).toDouble()) ? (current(task) as num).toDouble() : null,
                                              hint: Text('${((current(task) as num) * 100).round()}%'),
                                              items: [
                                                for (final v in [
                                                  0.0,
                                                  .25,
                                                  .5,
                                                  .75,
                                                  1.0
                                                ])
                                                  DropdownMenuItem(
                                                      value: v,
                                                      child: Text(
                                                          '${(v * 100).round()}%'))
                                              ],
                                              onChanged: busy || !authorized
                                                  ? null
                                                  : (v) {
                                                      if (v != null)
                                                        change(task, v);
                                                    })))
                              ]))
                  ]))
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final menus = <PopupMenuEntry<String>>[
      if (widget.uidProvider == null)
        const PopupMenuItem(value: 'contacts', child: Text('Colaboradores')),
      if (data != null && pending.isEmpty && store != null)
        const PopupMenuItem(
            value: 'copy', child: Text('Salvar c\u00f3pia no sistema')),
    ];
    return PopScope(
        canPop: !busy && pending.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) close();
        },
        child: Dialog(
          insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
              width: 1240,
              height: size.height * .92,
              child: DefaultTabController(
                  length: 2,
                  child: Column(children: [
                    SpreadsheetDialogHeader(
                        projectId: widget.project.id,
                        client: widget.project.client,
                        filename: data?['filename']?.toString() ?? '',
                        serviceType: widget.project.serviceType,
                        onClose: busy ? null : close,
                        moreActions: menus.isEmpty || !authorized
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Mais a\u00e7\u00f5es da planilha',
                                enabled: !busy,
                                itemBuilder: (_) => menus,
                                onSelected: (value) async {
                                  if (busy || !authorized) return;
                                  if (value == 'contacts') {
                                    await CompanyContacts.show(context);
                                    if (mounted && authorized)
                                      await loadContacts();
                                  } else if (value == 'copy' && data != null) {
                                    setState(() {
                                      busy = true;
                                      notice = null;
                                    });
                                    await remember(data!);
                                    if (mounted) setState(() => busy = false);
                                  }
                                })),
                    if (busy) const LinearProgressIndicator(minHeight: 2),
                    if (error != null || notice != null)
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(error ?? notice!,
                                      style: TextStyle(
                                          color: error == null
                                              ? colors.onSurface
                                              : colors.error))))),
                    TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorWeight: 3,
                        labelStyle:
                            const TextStyle(fontWeight: FontWeight.w600),
                        tabs: [
                          const Tab(text: 'Informa\u00e7\u00f5es de entrada'),
                          Tab(
                              text: projectChecklistSheet(
                                  widget.project.serviceType))
                        ]),
                    Expanded(
                        child: data == null || !authorized
                            ? Center(
                                child: Text(busy
                                    ? 'Carregando a planilha...'
                                    : 'Nenhuma planilha carregada.'))
                            : TabBarView(children: [entry(), checklist()])),
                    SpreadsheetDialogFooter(
                        pendingCount: pending.length,
                        synchronization: synchronizationLabel,
                        actions: [
                          OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              onPressed: busy || !authorized ? null : load,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Recarregar do Excel')),
                          TextButton(
                              onPressed: busy ? null : close,
                              child: const Text('Cancelar')),
                          FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              onPressed: busy || !authorized || pending.isEmpty
                                  ? null
                                  : save,
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text('Salvar na planilha')),
                        ]),
                  ]))),
        ));
  }
}
