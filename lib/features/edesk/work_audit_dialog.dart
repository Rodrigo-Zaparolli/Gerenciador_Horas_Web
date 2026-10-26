import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/config/pilot_feature_access.dart';
import '../../data/services/edesk_credentials_service.dart';
import '../../data/services/edesk_endpoint.dart';
import '../../data/services/edesk_integration.dart';
import '../../data/services/edesk_python_web.dart';
import '../../domain/models/project_model.dart';
import 'work_audit.dart';

class WorkAuditDialog extends StatefulWidget {
  const WorkAuditDialog(
      {super.key, required this.projects, this.selectedProject});
  final List<ProjectModel> projects;
  final ProjectModel? selectedProject;
  static Future<void> show(BuildContext context, List<ProjectModel> projects,
      {ProjectModel? selectedProject}) {
    final user = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      return Future.value();
    }
    return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WorkAuditDialog(
            projects: projects, selectedProject: selectedProject));
  }

  @override
  State<WorkAuditDialog> createState() => _WorkAuditDialogState();
}

class _WorkAuditDialogState extends State<WorkAuditDialog> {
  final _number = TextEditingController(), _search = TextEditingController();
  final _selected = <String>{};
  final _fields = <String>{'name', 'status', 'start', 'end', 'percentage'};
  final _results =
      <({String reference, String? error, List<AuditFieldResult> fields})>[];
  String _mode = 'selected', _message = '', _progress = '';
  bool _busy = false, _stop = false;
  StreamSubscription<User?>? _auth;
  @override
  void initState() {
    super.initState();
    if (widget.selectedProject != null) {
      _selected.add(widget.selectedProject!.id);
    }
    final owner = FirebaseAuth.instance.currentUser?.uid;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != owner && mounted) {
        _stop = true;
        _results.clear();
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    _number.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final owner = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: owner?.uid, email: owner?.email)) {
      return;
    }
    List<AuditTarget> targets;
    try {
      if (_fields.isEmpty) {
        throw const FormatException('Selecione ao menos um campo.');
      }
      final matching = widget.projects
          .where((p) => p.id.trim() == _number.text.trim())
          .toList();
      targets = _mode == 'number'
          ? matching.isEmpty
              ? [AuditTarget(_number.text.trim())]
              : projectAuditTargets(matching)
          : projectAuditTargets(widget.projects
              .where((p) => _mode == 'all'
                  ? p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP'
                  : _selected.contains(p.id))
              .toList());
      if (targets.isEmpty ||
          targets.any((t) => !RegExp(r'^\d+$').hasMatch(t.number))) {
        throw const FormatException(
            'Selecione projetos ou informe uma solicitação válida.');
      }
    } on FormatException catch (error) {
      setState(() => _message = error.message);
      return;
    }
    setState(() {
      _busy = true;
      _stop = false;
      _message = '';
      _results.clear();
    });
    try {
      final credentials = await EdeskCredentialsService().ler();
      if (credentials == null) {
        throw StateError(
            'Configure suas credenciais nas configurações da integração E-Desk.');
      }
      final url = await edeskEndpointSettings.currentUrl();
      for (var index = 0; index < targets.length; index++) {
        if (_stop || FirebaseAuth.instance.currentUser?.uid != owner?.uid) {
          break;
        }
        final target = targets[index];
        setState(() => _progress =
            '${index + 1}/${targets.length} · Solicitação ${target.number}');
        final operationId = 'audit-${DateTime.now().microsecondsSinceEpoch}';
        var polling = false;
        final timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
          if (polling) return;
          polling = true;
          try {
            final state = await EdeskIntegrationApi.call('/api/edesk/status',
                baseUrl: url);
            if (timer.isActive &&
                mounted &&
                _busy &&
                state['operationId'] == operationId) {
              setState(() => _progress =
                  '${index + 1}/${targets.length} · Solicitação ${target.number} · ${state['stage'] == 'login' ? 'Aguardando login' : 'Consultando trabalhos'}');
            }
          } catch (_) {
            /* A progress failure does not restart a query. */
          } finally {
            polling = false;
          }
        });
        try {
          final response = await EdeskWebClient(apiUrl: url).execute(
              requestJson: jsonEncode({
                'edeskCredenciais': credentials,
                'solicitacoes': [target.toJson()],
                'includeHours': _fields.contains('hours')
              }),
              enviar: false,
              script: 'edesk_conferencia.py',
              operationId: operationId);
          if (!mounted ||
              FirebaseAuth.instance.currentUser?.uid != owner?.uid) {
            break;
          }
          if (!response.confirmed) {
            _results.add((
              reference: target.number,
              error: response.message,
              fields: <AuditFieldResult>[]
            ));
            // Global setup/connection failures must not launch N failed browsers.
            _stop = true;
          } else {
            final receipt =
                jsonDecode(response.responseBody) as Map<String, dynamic>;
            for (final raw in receipt['rows'] as List) {
              final row = Map<String, dynamic>.from(raw as Map);
              final work = row['idTrabalho']?.toString() ?? '';
              _results.add((
                reference: '${target.number}${work.isEmpty ? '' : '/$work'}',
                error:
                    row['error']?.toString() ?? row['hoursError']?.toString(),
                fields: compareAuditWork(
                    target.expected[work] ?? {},
                    Map<String, dynamic>.from(row['values'] as Map? ?? {}),
                    _fields)
              ));
            }
          }
        } finally {
          timer.cancel();
        }
        setState(() {});
      }
      if (mounted && FirebaseAuth.instance.currentUser?.uid == owner?.uid) {
        setState(() => _message = auditSummary(
            _results.map((result) => result.fields),
            hasErrors: _results.any((result) => result.error != null),
            interrupted: _stop));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Não foi possível concluir a conferência. Verifique as credenciais e a integração E-Desk. Resultados já obtidos foram mantidos.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.projects.where((p) => '${p.id} ${p.client}'
        .toLowerCase()
        .contains(_search.text.toLowerCase()));
    return PopScope(
        canPop: !_busy,
        child: Dialog(
            child: SizedBox(
          width: 1050,
          height: MediaQuery.sizeOf(context).height * .88,
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Conferir trabalhos no E-Desk',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'Consulta · Nenhuma alteração será salva no app ou no E-Desk. Campos sem equivalente no app aparecem como “Somente consulta”.'),
                    const SizedBox(height: 12),
                    Expanded(
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                          DropdownButtonFormField<String>(
                              initialValue: _mode,
                              decoration: const InputDecoration(
                                  labelText: 'O que conferir'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text('Todos os projetos ativos')),
                                DropdownMenuItem(
                                    value: 'selected',
                                    child: Text('Projetos selecionados')),
                                DropdownMenuItem(
                                    value: 'number',
                                    child: Text('Informar solicitação'))
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() => _mode = value!)),
                          if (_mode == 'number')
                            TextField(
                                controller: _number,
                                enabled: !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Número da solicitação')),
                          if (_mode == 'selected') ...[
                            TextField(
                                controller: _search,
                                enabled: !_busy,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                    labelText: 'Pesquisar projeto')),
                            SizedBox(
                                height: 180,
                                child: ListView(children: [
                                  for (final p in visible)
                                    CheckboxListTile(
                                        dense: true,
                                        title: Text('${p.id} · ${p.client}'),
                                        value: _selected.contains(p.id),
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(() {
                                                  if (value == true) {
                                                    _selected.add(p.id);
                                                  } else {
                                                    _selected.remove(p.id);
                                                  }
                                                }))
                                ])),
                          ],
                          const SizedBox(height: 10),
                          Wrap(spacing: 10, children: [
                            for (final entry in auditFields.entries)
                              FilterChip(
                                  label: Text(entry.value),
                                  selected: _fields.contains(entry.key),
                                  onSelected: _busy
                                      ? null
                                      : (value) => setState(() {
                                            if (value) {
                                              _fields.add(entry.key);
                                            } else {
                                              _fields.remove(entry.key);
                                            }
                                          }))
                          ]),
                          if (_busy) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            Text(_progress)
                          ],
                          if (_message.isNotEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: SelectableText(_message)),
                          for (final result in _results)
                            Card(
                                child: ExpansionTile(
                              initiallyExpanded: result.error != null ||
                                  result.fields
                                      .any((f) => f.state == 'Divergência'),
                              title: Text(result.reference),
                              subtitle: Text(result.error ??
                                  (result.fields
                                          .any((f) => f.state == 'Divergência')
                                      ? 'Divergência encontrada'
                                      : result.fields.isNotEmpty &&
                                              result.fields.every(
                                                  (f) => f.state == 'Igual')
                                          ? 'Conferido'
                                          : 'Conferência parcial / dados consultados')),
                              children: [
                                SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(columns: const [
                                      DataColumn(label: Text('Campo')),
                                      DataColumn(label: Text('App')),
                                      DataColumn(label: Text('E-Desk')),
                                      DataColumn(label: Text('Resultado'))
                                    ], rows: [
                                      for (final f in result.fields)
                                        DataRow(cells: [
                                          DataCell(Text(auditFields[f.field]!)),
                                          DataCell(SelectableText(
                                              f.app.isEmpty ? '—' : f.app)),
                                          DataCell(SelectableText(
                                              f.edesk.isEmpty ? '—' : f.edesk)),
                                          DataCell(Text(f.state))
                                        ])
                                    ]))
                              ],
                            )),
                        ]))),
                    const SizedBox(height: 12),
                    Wrap(alignment: WrapAlignment.end, spacing: 12, children: [
                      TextButton(
                          onPressed:
                              _busy ? null : () => Navigator.pop(context),
                          child: const Text('Fechar')),
                      if (_busy)
                        TextButton(
                            onPressed: _stop
                                ? null
                                : () => setState(() => _stop = true),
                            child: const Text('Parar após esta solicitação')),
                      FilledButton.icon(
                          onPressed: _busy ? null : _run,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Iniciar conferência')),
                    ]),
                  ])),
        )));
  }
}
