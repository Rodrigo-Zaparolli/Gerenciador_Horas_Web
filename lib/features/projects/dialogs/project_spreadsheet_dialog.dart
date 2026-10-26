import 'dart:async';
import 'spreadsheet_store.dart';
import 'spreadsheet_sheet_settings.dart';
import 'company_contacts.dart';
import 'project_spreadsheet_kind.dart';
import 'checklist_status_preview.dart';
import 'checklist_live_preview.dart';
import 'checklist_stage_dialog.dart';
import 'workbook_sheet_dialog.dart';
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
      this.store,
      this.sheetSettingsStore});
  final Future<List<CompanyContact>> Function()? contactsLoader;
  final SpreadsheetStore? store;
  final SpreadsheetSheetSettingsStore? sheetSettingsStore;
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
  final Set<String> hiddenPasswords = {};
  Map<String, dynamic>? data;
  Map<String, String> sheetNames = {};
  SpreadsheetSheetSettingsStore? get settingsStore =>
      widget.sheetSettingsStore ??
      (widget.transport == null
          ? FirebaseSpreadsheetSheetSettingsStore()
          : null);
  bool matches(Map<String, dynamic> result, {Map<String, String>? names}) {
    final selected = names ?? sheetNames;
    return spreadsheetMatchesProject(result, widget.project.serviceType,
        checklistSheet: selected['checklist'], entrySheet: selected['entry']);
  }

  String? error, notice, owner;
  bool busy = false, settingsReady = false;
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

  bool _stageDialogOpen = false;
  Future<void> _fileRequestTail = Future<void>.value();

  Future<Map<String, dynamic>> request(String action,
      {String? revision,
      List<Map<String, dynamic>>? changes,
      Map<String, String>? selectedSheets,
      bool Function()? isCurrent}) {
    final requestedOwner = owner;
    final names = Map<String, String>.from(selectedSheets ?? sheetNames);
    final edits = changes?.map((c) => Map<String, dynamic>.from(c)).toList();
    final result = _fileRequestTail.then((_) {
      if (!mounted ||
          !authorized ||
          owner != requestedOwner ||
          isCurrent != null && !isCurrent()) {
        throw StateError('A conta mudou ou o editor foi fechado.');
      }
      return _performRequest(action,
          revision: revision, changes: edits, selectedSheets: names);
    });
    _fileRequestTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>> _performRequest(String action,
      {String? revision,
      List<Map<String, dynamic>>? changes,
      Map<String, String>? selectedSheets}) async {
    final selected = selectedSheets ?? sheetNames;
    if (widget.transport != null) {
      return widget.transport!({
        'action': action,
        'reference': widget.project.excelLink,
        'serviceType': widget.project.serviceType,
        if (selected.isNotEmpty) 'sheetNames': selected,
        if (revision != null) 'revision': revision,
        if (changes != null) 'changes': changes
      });
    }
    final result = await NativeLocalFiles.call(action,
        reference: widget.project.excelLink,
        projectId: widget.project.id,
        projectField: 'excelLink',
        serviceType: widget.project.serviceType,
        sheetNames: selected.isEmpty ? null : selected,
        revision: revision,
        changes: changes);
    if (mounted && authorized && result['reference'] is String) {
      widget.project.excelLink = result['reference'] as String;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    owner = uid;
    livePreview = ChecklistLivePreview(calculate: calculateStatus);
    if (widget.uidProvider == null) {
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
    }
    openConfigured();
    if (widget.uidProvider == null || widget.contactsLoader != null) {
      loadContacts();
    }
  }

  Future<void> openConfigured() async {
    if (!authorized) return;
    setState(() => busy = true);
    try {
      final names = await settingsStore?.load(
              owner!, widget.project.id, widget.project.excelLink ?? '') ??
          <String, String>{};
      if (!mounted || !authorized) return;
      setState(() {
        sheetNames = names;
        settingsReady = true;
        busy = false;
      });
      await openSaved();
    } catch (e) {
      if (mounted && authorized) {
        setState(() {
          busy = false;
          error =
              'Não foi possível carregar a configuração de abas. Use Abas para conferir antes de editar. $e';
        });
      }
    }
  }

  Future<void> openAllSheets() async {
    if (busy || !authorized || !await discard() || !mounted) return;
    await livePreview.pauseAndWait();
    if (!mounted || !authorized) return;
    setState(() {
      pending.clear();
      calculatedEmails.clear();
    });
    try {
      final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => WorkbookSheetDialog(
              allowed: () => mounted && authorized,
              call: (args) async {
                if (widget.transport != null) {
                  return widget.transport!(
                      {...args, 'reference': widget.project.excelLink});
                }
                return NativeLocalFiles.call(args['action'] as String,
                    reference: widget.project.excelLink,
                    projectId: widget.project.id,
                    projectField: 'excelLink',
                    worksheet: args['worksheet'] as String?,
                    firstRow: args['firstRow'] as int?,
                    firstColumn: args['firstColumn'] as int?,
                    revision: args['revision'] as String?,
                    changes: (args['changes'] as List?)
                        ?.cast<Map<String, dynamic>>());
              }));
      if (changed == true && mounted && authorized) {
        pending.clear();
        await load();
      }
    } finally {
      if (mounted && authorized) livePreview.resume(clear: true);
    }
  }

  Future<void> configureSheets() async {
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final listed = await request('excel-editor-sheets');
      if (!mounted || !authorized) return;
      final names = (listed['sheetNames'] as List).cast<String>();
      setState(() => busy = false);
      final selected = await selectSpreadsheetSheets(context, names, {
        'entry': sheetNames['entry'] ?? 'Informações de entrada',
        'checklist': sheetNames['checklist'] ??
            projectChecklistSheet(widget.project.serviceType),
      });
      if (selected == null || !mounted || !authorized) return;
      setState(() => busy = true);
      final result =
          await request('excel-editor-read', selectedSheets: selected);
      if (!mounted || !authorized) return;
      if (!matches(result, names: selected)) {
        throw StateError('A integração não confirmou as abas selecionadas.');
      }
      await settingsStore?.save(
          owner!, widget.project.id, widget.project.excelLink ?? '', selected);
      if (!mounted || !authorized) return;
      setState(() {
        sheetNames = selected;
        settingsReady = true;
        data = result;
        pending.clear();
        calculatedEmails.clear();
        notice = 'Abas configuradas para este projeto.';
      });
      await remember(result);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) livePreview.resume(clear: true);
      }
    }
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
      if (mounted && authorized) {
        setState(
            () => notice = 'Não foi possível carregar os colaboradores: $e');
      }
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
      if (saved != null && matches(saved)) {
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
      if (mounted && authorized && warning != null) {
        setState(() => notice = warning);
      }
    }
  }

  Future<void> remember(Map<String, dynamic> result) async {
    if (!authorized || store == null) return;
    final stamp = DateTime.now().toIso8601String();
    try {
      await store!.save(
          owner!, widget.project.id, widget.project.excelLink ?? '', result);
      if (mounted && authorized) {
        setState(() => data = {...result, 'syncedAt': stamp});
      }
    } catch (e) {
      if (mounted && authorized) {
        setState(() => notice =
            'O Excel foi lido/gravado, mas a cópia no sistema não foi atualizada. Use Salvar cópia no sistema para tentar novamente. $e');
      }
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
    if (!settingsReady) {
      await openConfigured();
      return;
    }
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final result = await request('excel-editor-read');
      if (!matches(result)) {
        throw StateError(
            'A integração retornou um checklist diferente do tipo do projeto. Atualize e reinicie a integração v25 para usar Professional/Maker.');
      }
      if (mounted && authorized) {
        setState(() {
          data = result;
          pending.clear();
          calculatedEmails.clear();
          notice = null;
        });
      }
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
    if (!mounted || !authorized || data == null) {
      throw StateError('A conta mudou.');
    }
    final result = await request('excel-editor-preview',
        revision: data!['revision'] as String,
        changes: pending.values.toList());
    if (!mounted || !authorized) throw StateError('A conta mudou.');
    if (result['preview'] != true ||
        result['statusPreview'] is! Map ||
        !matches(result)) {
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
      if (result['saved'] != true) {
        throw StateError(
            'A gravação não foi confirmada. Recarregue para conferir antes de tentar novamente.');
      }
      if (!matches(result)) {
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
      if (mounted && authorized) {
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
      }
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
    if (kind == 'yesno') {
      return DropdownButtonFormField<String>(
          key: ValueKey('${data!['revision']}:${keyOf(field)}'),
          initialValue: current(field) as String,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: 'Sim', child: Text('Sim')),
            DropdownMenuItem(value: 'Não', child: Text('Não'))
          ],
          onChanged: busy ? null : (v) => change(field, v));
    }
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
                  onPressed: busy || field['readOnly'] == true
                      ? null
                      : () => change(field, ''),
                  icon: const Icon(Icons.clear, size: 16))),
          onTap: busy || field['readOnly'] == true
              ? null
              : () async {
                  final selected = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200));
                  if (selected != null && mounted && authorized) {
                    change(field, selected.toIso8601String().substring(0, 10));
                  }
                });
    }
    return TextFormField(
        key: ValueKey(
            '${data!['revision']}:${keyOf(field)}:${field['label'].toString().endsWith('— E-mail') ? current(field) : ''}'),
        initialValue: current(field).toString(),
        enabled: !busy && authorized,
        readOnly: field['readOnly'] == true,
        obscureText: label.toLowerCase().contains('senha') &&
            hiddenPasswords.contains(keyOf(field)),
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: label.toLowerCase().contains('senha')
                ? IconButton(
                    tooltip: hiddenPasswords.contains(keyOf(field))
                        ? 'Mostrar senha'
                        : 'Ocultar senha',
                    icon: Icon(hiddenPasswords.contains(keyOf(field))
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() {
                          final key = keyOf(field);
                          if (!hiddenPasswords.remove(key)) {
                            hiddenPasswords.add(key);
                          }
                        }))
                : null,
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
    final fields = (data!['fields'] as List)
        .cast<Map<String, dynamic>>()
        .where((f) => f['timeline'] != true)
        .toList();
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

  Widget timeline() {
    final fields = (data!['fields'] as List)
        .cast<Map<String, dynamic>>()
        .where((f) => f['timeline'] == true)
        .toList();
    if (fields.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Recarregue do Excel com a integração atualizada para carregar a tabela Detalhes do Projeto da guia Implantação - Linha do Tempo.')));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Ajuste as datas dos eventos. As datas calculadas e o resumo da planilha são preservados.'),
      const SizedBox(height: 16),
      for (final field in fields)
        Padding(
            padding: const EdgeInsets.only(bottom: 16), child: input(field)),
    ]);
  }

  Future<void> editStage(String group, List<Map<String, dynamic>> tasks) async {
    if (busy || !authorized || _stageDialogOpen) return;
    _stageDialogOpen = true;
    var routeActive = true;
    final revision = data?['revision'];
    livePreview.pause();
    if (!mounted || !authorized || busy || data?['revision'] != revision) {
      _stageDialogOpen = false;
      if (mounted && authorized) livePreview.resume();
      return;
    }
    Map<String, double>? result;
    try {
      result = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChecklistStageDialog(
            stage: group,
            calculatePreview: (values) async {
              if (!mounted ||
                  !authorized ||
                  busy ||
                  data?['revision'] != revision) {
                throw StateError('A conta ou a planilha mudou.');
              }
              final changes = {...pending};
              for (final task in tasks) {
                final key = keyOf(task);
                final value = values[key];
                if (task['readOnly'] == true || value == null) continue;
                if (value == task['value']) {
                  changes.remove(key);
                } else {
                  changes[key] = {
                    'sheet': task['sheet'],
                    'cell': task['cell'],
                    'before': task['value'],
                    'value': value
                  };
                }
              }
              final response = await request('excel-editor-preview',
                  revision: revision as String,
                  changes: changes.values.toList(),
                  isCurrent: () => routeActive);
              if (!mounted ||
                  !authorized ||
                  data?['revision'] != revision ||
                  response['preview'] != true ||
                  response['statusPreview'] is! Map ||
                  !matches(response)) {
                throw StateError(
                    'A planilha mudou ou a prévia não foi confirmada.');
              }
              return Map<String, dynamic>.from(
                  response['statusPreview'] as Map);
            },
            tasks: tasks,
            values: {
              for (final task in tasks)
                keyOf(task): (current(task) as num).toDouble()
            },
            canApply: () =>
                mounted &&
                authorized &&
                !busy &&
                data?['revision'] == revision),
      );
    } finally {
      routeActive = false;
      _stageDialogOpen = false;
      if (mounted && authorized) livePreview.resume();
    }
    if (result == null ||
        !mounted ||
        !authorized ||
        busy ||
        data?['revision'] != revision) {
      return;
    }
    for (final task in tasks) {
      final value = result[keyOf(task)];
      if (value != null && task['readOnly'] != true) change(task, value);
    }
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
    final filters = Padding(
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
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon: Icon(Icons.search)),
                          onChanged: (v) => setState(() => search = v))),
                  for (final item in ['Todas', 'Pendentes', 'Concluídas'])
                    ChoiceChip(
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        label: Text(item),
                        selected: filter == item,
                        onSelected: (_) => setState(() => filter = item)),
                  Text('${shown.length} tarefas',
                      style: Theme.of(context).textTheme.bodySmall),
                ])));
    final cards = <Widget>[
      for (final group in shown.map((f) => f['group'] as String).toSet())
        Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: ValueKey('checklist-stage-$group'),
              leading: const Icon(Icons.checklist_outlined),
              title: Text(group,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${shown.where((f) => f['group'] == group).length} tarefas'),
              trailing: const Icon(Icons.open_in_new),
              onTap: busy || !authorized
                  ? null
                  : () => editStage(
                      group, all.where((f) => f['group'] == group).toList()),
            ))
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      final preview = ChecklistStatusPanel(
          controller: livePreview, unsaved: pending.isNotEmpty, compact: wide);
      if (wide) {
        return Row(
            key: const ValueKey('checklist-side-by-side'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: preview),
              const SizedBox(width: 8),
              SizedBox(
                  width: 300,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        filters,
                        Expanded(
                            child: ListView(
                                key: const ValueKey('checklist-task-list'),
                                primary: false,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                children: cards)),
                      ])),
            ]);
      }
      return CustomScrollView(
          key: const ValueKey('checklist-stacked-scroll'),
          primary: false,
          slivers: [
            SliverToBoxAdapter(child: preview),
            SliverToBoxAdapter(child: filters),
            SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(child: Column(children: cards))),
          ]);
    });
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
                  length: 3,
                  child: Column(children: [
                    SpreadsheetDialogHeader(
                        projectId: widget.project.id,
                        client: widget.project.client,
                        filename: data?['filename']?.toString() ?? '',
                        serviceType: widget.project.serviceType,
                        onClose: busy ? null : close,
                        sheetAction: PopupMenuButton<String>(
                            tooltip: 'Guias da planilha',
                            enabled: !busy && authorized,
                            icon: const Icon(Icons.table_chart_outlined),
                            itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'all',
                                      child: Text('Todas as guias')),
                                  PopupMenuItem(
                                      value: 'configure',
                                      child: Text('Configurar abas do modelo'))
                                ],
                            onSelected: (value) {
                              if (value == 'all') {
                                openAllSheets();
                              } else {
                                configureSheets();
                              }
                            }),
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
                                    if (mounted && authorized) {
                                      await loadContacts();
                                    }
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
                                  widget.project.serviceType,
                                  override: sheetNames['checklist'])),
                          const Tab(
                              text: 'Implanta\u00e7\u00e3o - Linha do Tempo')
                        ]),
                    Expanded(
                        child: data == null || !authorized
                            ? Center(
                                child: Text(busy
                                    ? 'Carregando a planilha...'
                                    : 'Nenhuma planilha carregada.'))
                            : TabBarView(
                                children: [entry(), checklist(), timeline()])),
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
