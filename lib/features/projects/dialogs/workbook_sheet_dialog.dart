import 'workbook_confirmation.dart';
import 'consultoria_row_drafts.dart';
import 'project_worksheet_preference.dart';
import 'spreadsheet_dialog_chrome.dart';
import 'cronograma_table.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class WorkbookSheetDialog extends StatefulWidget {
  const WorkbookSheetDialog(
      {super.key,
      required this.call,
      required this.allowed,
      this.projectId,
      this.client = '',
      this.serviceType = '',
      this.initialWorksheet,
      this.onWorksheetOpened,
      this.onMappedWorksheet});
  final Future<void> Function(String)? onMappedWorksheet;
  final String? projectId;
  final String client, serviceType;
  bool get projectLayout => projectId != null;
  final String? initialWorksheet;
  final Future<void> Function(String)? onWorksheetOpened;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) call;
  final bool Function() allowed;
  @override
  State<WorkbookSheetDialog> createState() => _WorkbookSheetDialogState();
}

class _WorkbookSheetDialogState extends State<WorkbookSheetDialog> {
  List<String> names = [];
  String? selected, error, savedWorksheet;
  Map<String, dynamic>? data;
  final Map<String, Map<String, dynamic>> edits = {};
  final rows = ConsultoriaRowDrafts();
  bool get dirty => edits.isNotEmpty || rows.dirty;
  int get pendingCount => edits.length + rows.count;
  bool busy = false,
      saved = false,
      saving = false,
      closing = false,
      rawGrid = false;
  bool get structured =>
      data?['scheduleTable'] == true || data?['consultoriaTable'] == true;
  int row = 1, column = 1, selectionEpoch = 0;
  final vertical = ScrollController(), horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.projectLayout && widget.initialWorksheet != null) {
      final schedule = widget.initialWorksheet!.toLowerCase() == 'cronogramas';
      unawaited(
          open(widget.initialWorksheet!, schedule ? 5 : 1, schedule ? 2 : 1)
              .then((_) {
        if (mounted) return list(autoOpen: false);
      }));
    } else {
      list();
    }
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> args) async {
    final reading = const {'excel-editor-read', 'excel-editor-sheets'}
        .contains(args['action']);
    for (var attempt = 0;; attempt++) {
      if (!mounted || !widget.allowed()) {
        throw StateError('A conta mudou ou o editor foi fechado.');
      }
      try {
        final result = await widget.call(args);
        if (!mounted || !widget.allowed()) {
          throw StateError('A conta mudou ou o editor foi fechado.');
        }
        return result;
      } catch (e) {
        final occupied = e.toString().toLowerCase().contains(
            'aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento');
        if (!reading ||
            !occupied ||
            attempt >= 11 ||
            !mounted ||
            !widget.allowed()) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> list({bool autoOpen = true}) async {
    setState(() => busy = true);
    try {
      final result = await request({'action': 'excel-editor-sheets'});
      if (mounted) {
        setState(() => names = (result['sheetNames'] as List).cast<String>());
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (autoOpen &&
        mounted &&
        widget.allowed() &&
        widget.initialWorksheet != null &&
        names.contains(widget.initialWorksheet)) {
      final schedule = widget.initialWorksheet!.toLowerCase() == 'cronogramas';
      await open(widget.initialWorksheet!, schedule ? 5 : 1, schedule ? 2 : 1);
    }
  }

  Future<void> close() async {
    if (saving || closing) return;
    closing = true;
    var popped = false;
    try {
      if (await discard() && mounted) {
        popped = true;
        Navigator.pop(context, saved);
      }
    } finally {
      if (!popped) closing = false;
    }
  }

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
            context: context,
            builder: (_) => const WorkbookConfirmation(
                title: 'Descartar altera\u00e7\u00f5es desta guia?',
                message:
                    'H\u00e1 altera\u00e7\u00f5es que ainda n\u00e3o foram salvas na planilha.',
                cancelLabel: 'Continuar editando',
                confirmLabel: 'Descartar')) ==
        true;
  }

  Future<void> open(String name, int firstRow, int firstColumn) async {
    if (busy) return;
    if (!await discard()) {
      if (mounted) setState(() => selectionEpoch++);
      return;
    }
    if (!mounted || busy) return;
    if (widget.onMappedWorksheet != null && mappedWorksheetTab(name) != null) {
      await widget.onMappedWorksheet!(name);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await request({
        'action': 'excel-editor-read',
        'worksheet': name,
        'firstRow': firstRow,
        'firstColumn': firstColumn
      });
      if (result['worksheet'] != name ||
          result['firstRow'] != firstRow ||
          result['firstColumn'] != firstColumn) {
        throw StateError(
            'A integração não oferece a edição de todas as guias. Atualize a integração antes de continuar.');
      }
      if (name.toLowerCase() == 'cronogramas' &&
          result['worksheetTypesVersion'] != 2) {
        throw StateError(
            'Atualize a integração local para editar o cronograma com horários e percentuais. Nenhuma alteração foi enviada.');
      }
      if (name.toLowerCase() == 'cronogramas' &&
          result['scheduleTable'] != true) {
        throw StateError(
            'A tabela do Cronograma não foi reconhecida. O editor antigo não será aberto. '
            'Confira se a guia contém a tabela com Data, horários, Status e Trabalho / Descrição. '
            'Se a integração já está na v50, envie um print desta guia para conferir o modelo. '
            'Nenhuma alteração foi enviada.');
      }
      if (name.toLowerCase().contains('consultoria') &&
          result['consultoriaTable'] != true) {
        if (result.containsKey('consultoriaTable')) {
          throw StateError(
              'A tabela de Consultoria desta guia n\u00e3o foi reconhecida. Confira a guia selecionada e o modelo da planilha. Nenhuma c\u00e9lula foi alterada.');
        }
        throw StateError(
            'A tabela de Consultoria precisa da integra\u00e7\u00e3o v52. Atualize e reinicie a integra\u00e7\u00e3o; nenhuma c\u00e9lula foi alterada.');
      }
      if (mounted) {
        setState(() {
          rawGrid = false;
          selected = name;
          row = firstRow;
          column = firstColumn;
          data = result;
          edits.clear();
          rows.clear();
        });
        if (savedWorksheet != name && widget.onWorksheetOpened != null) {
          savedWorksheet = name;
          unawaited(Future<void>.sync(() => widget.onWorksheetOpened!(name))
              .catchError((Object _) {
            if (savedWorksheet == name) savedWorksheet = null;
            if (mounted && selected == name) {
              setState(() => error =
                  'A guia abriu, mas não foi possível salvar a preferência. Tente abrir novamente quando a conexão voltar.');
            }
          }));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          selectionEpoch++;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || data == null || !dirty) return;
    setState(() {
      busy = true;
      saving = true;
      error = null;
    });
    try {
      final result = await request({
        'action': 'excel-editor-write',
        'worksheet': selected,
        'firstRow': row,
        'firstColumn': column,
        'revision': data!['revision'],
        'changes': rows.payload(edits)
      });
      if (rows.dirty &&
          (result['rowsApplied'] is! Map ||
              (result['rowsApplied'] as Map)['added'] != rows.added.length ||
              (result['rowsApplied'] as Map)['deleted'] !=
                  rows.deleted.length)) {
        throw StateError(
            'O Excel n\u00e3o confirmou a altera\u00e7\u00e3o das linhas. Recarregue para conferir antes de tentar novamente.');
      }
      if (result['saved'] != true || result['worksheet'] != selected) {
        throw StateError('A gravação da guia não foi confirmada.');
      }
      if (mounted) {
        setState(() {
          data = result;
          edits.clear();
          rows.clear();
          saved = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          saving = false;
        });
      }
    }
  }

  bool rowEditingAllowed() {
    if (busy || !widget.allowed()) return false;
    if (data?['consultoriaRowOperationsVersion'] != 1) {
      setState(() => error =
          'Atualize e reinicie a integra\u00e7\u00e3o v53 para adicionar ou excluir encontros.');
      return false;
    }
    return true;
  }

  void addRow() {
    if (!rowEditingAllowed() || selected == null) return;
    setState(() => rows.add(
        selected!,
        (data?['consultoriaDetails'] as Map?)?['description']?.toString() ??
            'Consultoria'));
  }

  Future<void> deleteRow(int row) async {
    if (!rowEditingAllowed()) return;
    if (!rows.added.containsKey(row)) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => const WorkbookConfirmation(
              title: 'Excluir encontro?',
              message:
                  'A linha e seus dados ser\u00e3o removidos do Excel ao salvar na planilha. Voc\u00ea pode desfazer antes de salvar.',
              confirmLabel: 'Marcar para excluir'));
      if (confirmed != true || !mounted || !widget.allowed() || busy) return;
    }
    setState(() => rows.remove(row, edits));
  }

  void setField(Map<String, dynamic> field, dynamic value) {
    if (busy || !widget.allowed()) return;
    setState(() {
      if (value == field['value']) {
        edits.remove(field['cell']);
      } else {
        edits[field['cell']] = {
          'sheet': selected,
          'cell': field['cell'],
          'before': field['value'],
          'value': value
        };
      }
    });
  }

  Future<void> edit(Map<String, dynamic> field) async {
    if (busy || field['readOnly'] == true || !widget.allowed()) return;
    final address = field['cell'] as String;
    final current = edits[address]?['value'] ?? field['value'];
    dynamic next;
    if (field['kind'] == 'date') {
      final date = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(current.toString()) ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2200));
      if (date == null) return;
      next = date.toIso8601String().substring(0, 10);
    } else {
      final controller = TextEditingController(
          text: field['percent'] == true && current is num
              ? (current * 100).toString()
              : current.toString());
      final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text('$selected · $address'),
                content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                        helperText: field['percent'] == true
                            ? 'Percentual de 0 a 100'
                            : field['kind'] == 'time'
                                ? 'Horário no formato HH:mm'
                                : null),
                    autofocus: true,
                    maxLength: 10000,
                    keyboardType: field['kind'] == 'number'
                        ? const TextInputType.numberWithOptions(
                            decimal: true, signed: true)
                        : TextInputType.multiline),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Aplicar'))
                ],
              ));
      // The route keeps the text field alive for its exit animation.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (result == null) return;
      next = field['kind'] == 'number'
          ? double.tryParse(result.replaceAll(',', '.'))
          : field['value'] == ''
              ? double.tryParse(result.replaceAll(',', '.')) ?? result
              : result;
      if (field['percent'] == true && next is num) next = next / 100;
      if (next == null || next is double && !next.isFinite) {
        if (mounted) setState(() => error = 'Informe um número válido.');
        return;
      }
    }
    if (!mounted || !widget.allowed()) return;
    setState(() {
      error = null;
      if (next == field['value']) {
        edits.remove(address);
      } else {
        edits[address] = {
          'sheet': selected,
          'cell': address,
          'before': field['value'],
          'value': next
        };
      }
    });
  }

  @override
  void dispose() {
    vertical.dispose();
    horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      ...(data?['fields'] as List? ?? []).cast<Map<String, dynamic>>(),
      ...rows.added.values.expand((f) => f)
    ];
    final dialog = AlertDialog(
      title: Text(data?['scheduleTable'] == true
          ? 'Planilha do projeto · Cronograma'
          : 'Todas as guias da planilha'),
      content: SizedBox(
          width: 1100,
          height: MediaQuery.sizeOf(context).height * .65,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (busy) const LinearProgressIndicator(),
            if (widget.projectLayout)
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final name in {
                      names.firstWhere(
                          (n) => n.toLowerCase().contains('entrada'),
                          orElse: () => 'Informa\u00e7\u00f5es de entrada'),
                      names.firstWhere(
                          (n) => n.toLowerCase().contains('checklist'),
                          orElse: () => 'Checklist-Processo'),
                      if (!widget.serviceType
                              .toLowerCase()
                              .contains('consultoria') ||
                          widget.serviceType.toLowerCase().contains('catalog'))
                        'Cronogramas',
                      ...names.where(
                          (n) => n.toLowerCase().contains('consultoria')),
                    })
                      Container(
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      width: 3,
                                      color: (selected ??
                                                  widget.initialWorksheet) ==
                                              name
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.transparent))),
                          child: TextButton(
                              onPressed: busy || !names.contains(name)
                                  ? null
                                  : () => open(
                                      name,
                                      name == 'Cronogramas' ? 5 : 1,
                                      name == 'Cronogramas' ? 2 : 1),
                              child: Text(name == 'Cronogramas'
                                  ? 'Cronograma'
                                  : name))),
                  ]))
            else
              DropdownButtonFormField<String>(
                  key: ValueKey('$selected-$selectionEpoch'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Guia do Excel'),
                  items: names
                      .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (name) {
                          if (name != null) {
                            final schedule =
                                name.toLowerCase() == 'cronogramas';
                            open(name, schedule ? 5 : 1, schedule ? 2 : 1);
                          }
                        }),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'Toque em uma célula para editar. Fórmulas e células protegidas ficam bloqueadas.')),
            if (data != null &&
                !structured &&
                (!widget.projectLayout || rawGrid))
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                IconButton(
                    tooltip: 'Linhas anteriores',
                    onPressed: busy || row == 1
                        ? null
                        : () => open(
                            selected!, (row - 25).clamp(1, 1048552), column),
                    icon: const Icon(Icons.keyboard_arrow_up)),
                Text('Linhas $row–${row + 24}'),
                IconButton(
                    tooltip: 'Próximas linhas',
                    onPressed: busy || row + 25 > 1048552
                        ? null
                        : () => open(selected!, row + 25, column),
                    icon: const Icon(Icons.keyboard_arrow_down)),
                IconButton(
                    tooltip: 'Colunas anteriores',
                    onPressed: busy || column == 1
                        ? null
                        : () =>
                            open(selected!, row, (column - 8).clamp(1, 16377)),
                    icon: const Icon(Icons.chevron_left)),
                Text('Colunas $column–${column + 7}'),
                IconButton(
                    tooltip: 'Próximas colunas',
                    onPressed: busy || column + 8 > 16377
                        ? null
                        : () => open(selected!, row, column + 8),
                    icon: const Icon(Icons.chevron_right)),
              ]),
            Expanded(
                child: structured
                    ? CronogramaTable(
                        fields: fields,
                        consultoria: data?['consultoriaTable'] == true,
                        contractHours: (data?['consultoriaDetails']
                                as Map?)?['contractedHours']
                            ?.toString(),
                        edits: edits,
                        busy: busy,
                        vertical: vertical,
                        horizontal: horizontal,
                        onEdit: edit,
                        addedRows: rows.added.keys.toSet(),
                        deletedRows: rows.deleted,
                        onAddRow: addRow,
                        onDeleteRow: deleteRow,
                        onUndoRow: (row) =>
                            setState(() => rows.deleted.remove(row)),
                        onEditValue: setField,
                        onStatus: setField)
                    : widget.projectLayout && !rawGrid && fields.isNotEmpty
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                const Text(
                                    'Esta guia ainda n\u00e3o possui uma tabela pr\u00f3pria neste editor.'),
                                TextButton(
                                    onPressed: () =>
                                        setState(() => rawGrid = true),
                                    child: const Text(
                                        'Ver c\u00e9lulas (avan\u00e7ado)')),
                              ]))
                        : fields.isEmpty
                            ? Center(
                                child: Text(busy
                                    ? 'Carregando a planilha...'
                                    : widget.projectLayout
                                        ? 'Use Recarregar do Excel para tentar novamente.'
                                        : 'Selecione uma guia para abrir.'))
                            : Scrollbar(
                                controller: vertical,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                    controller: vertical,
                                    child: SingleChildScrollView(
                                      controller: horizontal,
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(columns: [
                                        const DataColumn(label: Text('Linha')),
                                        for (var c = 0; c < 8; c++)
                                          DataColumn(
                                              label: Text(fields[c]['cell']
                                                  .toString()
                                                  .replaceAll(
                                                      RegExp(r'\d+'), '')))
                                      ], rows: [
                                        for (var r = 0;
                                            r < fields.length ~/ 8;
                                            r++)
                                          DataRow(cells: [
                                            DataCell(Text('${row + r}')),
                                            for (var c = 0; c < 8; c++)
                                              DataCell(
                                                  SizedBox(
                                                      width: 135,
                                                      child: Row(children: [
                                                        if (fields[r * 8 + c]
                                                                ['readOnly'] ==
                                                            true)
                                                          const Icon(
                                                              Icons
                                                                  .lock_outline,
                                                              size: 12),
                                                        Expanded(
                                                            child: Text(
                                                                (edits[fields[r * 8 + c]['cell']]
                                                                            ?[
                                                                            'value'] ??
                                                                        fields[r * 8 +
                                                                                c]
                                                                            [
                                                                            'display'] ??
                                                                        fields[r * 8 +
                                                                                c]
                                                                            [
                                                                            'value'])
                                                                    .toString(),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis)),
                                                      ])),
                                                  onTap: busy
                                                      ? null
                                                      : () => edit(
                                                          fields[r * 8 + c])),
                                          ])
                                      ]),
                                    )))),
            if (!widget.projectLayout)
              Text(
                  '${edits.length} alteração(ões) pendente(s)${saved ? ' · Última gravação confirmada' : ''}'),
          ])),
      actions: [
        TextButton(
            onPressed: saving ? null : close,
            child: Text(widget.projectLayout ? 'Cancelar' : 'Fechar')),
        FilledButton.icon(
            onPressed: busy || !dirty ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar na planilha'))
      ],
    );
    return PopScope(
        canPop: !saving && !dirty,
        child: !widget.projectLayout
            ? dialog
            : Dialog(
                insetPadding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 600 ? 8 : 24),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: SizedBox(
                    width: 1240,
                    height: MediaQuery.sizeOf(context).height * .92,
                    child: Column(children: [
                      SpreadsheetDialogHeader(
                          projectId: widget.projectId!,
                          client: widget.client,
                          filename: data?['filename']?.toString() ?? '',
                          serviceType: widget.serviceType,
                          onClose: saving ? null : close,
                          sheetAction: PopupMenuButton<String>(
                              tooltip: 'Escolher guia',
                              enabled: !busy,
                              icon: const Icon(Icons.table_chart_outlined),
                              itemBuilder: (_) => [
                                    for (final name in names)
                                      PopupMenuItem(
                                          value: name, child: Text(name))
                                  ],
                              onSelected: (name) => open(
                                  name,
                                  name == 'Cronogramas' ? 5 : 1,
                                  name == 'Cronogramas' ? 2 : 1))),
                      Expanded(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: dialog.content!)),
                      SpreadsheetDialogFooter(
                          pendingCount: pendingCount,
                          pendingLabel: rows.dirty ? rows.label : null,
                          synchronization: rows.dirty
                              ? 'As linhas ser\u00e3o adicionadas e removidas no Excel ao salvar.'
                              : saved
                                  ? '\u00daltima grava\u00e7\u00e3o confirmada'
                                  : 'Altere o Status de cada encontro para atualizar o progresso.',
                          actions: [
                            OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => open(
                                        selected ??
                                            widget.initialWorksheet ??
                                            'Cronogramas',
                                        (selected ?? widget.initialWorksheet) ==
                                                'Cronogramas'
                                            ? 5
                                            : row,
                                        (selected ?? widget.initialWorksheet) ==
                                                'Cronogramas'
                                            ? 2
                                            : column),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Recarregar do Excel')),
                            ...dialog.actions!,
                          ]),
                    ])),
              ));
  }
}
