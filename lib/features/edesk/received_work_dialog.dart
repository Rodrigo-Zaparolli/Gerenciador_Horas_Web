import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/config/pilot_feature_access.dart';
import '../../data/services/edesk_credentials_service.dart';
import '../../data/services/edesk_endpoint.dart';
import '../../data/services/edesk_python_web.dart';
import '../../data/services/firebase_service.dart';
import '../../data/services/received_work_store.dart';
import '../../domain/models/project_model.dart';
import 'received_work.dart';
import 'work_audit.dart';

void _closeReceivedRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route != null) Navigator.of(context).removeRoute(route);
}

class ReceivedWorkDialog extends StatefulWidget {
  const ReceivedWorkDialog(
      {super.key,
      this.importById = false,
      this.auth,
      this.query,
      this.loadTypes,
      this.loadExisting,
      this.importProject});
  final bool importById;
  final FirebaseAuth? auth;
  final Future<Map<String, dynamic>> Function(
      String script, Map<String, dynamic> data)? query;
  final Future<List<String>> Function()? loadTypes;
  final Future<ProjectModel?> Function(String request)? loadExisting;
  final Future<int> Function(ProjectModel project)? importProject;
  static Future<void> show(BuildContext context, {bool importById = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      return Future.value();
    }
    return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReceivedWorkDialog(importById: importById));
  }

  @override
  State<ReceivedWorkDialog> createState() => _ReceivedWorkDialogState();
}

class _ReceivedWorkDialogState extends State<ReceivedWorkDialog> {
  FirebaseAuth get _session => widget.auth ?? FirebaseAuth.instance;
  final _requestId = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  final _imported = <String>{};
  bool _busy = false;
  String _message =
      'Clique em Buscar na Minha Grid para consultar seus trabalhos no E-Desk.';
  StreamSubscription<User?>? _auth;
  late final String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = _session.currentUser?.uid;
    if (widget.importById) {
      _message =
          'Informe o ID da solicitação para buscar as etapas no E-Desk. Confira os dados antes de cadastrar no app.';
    }
    _auth = _session.authStateChanges().listen((user) {
      if (user?.uid != _owner && mounted) {
        setState(() => _rows.clear());
        _closeReceivedRoute(context);
      }
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    _requestId.dispose();
    super.dispose();
  }

  bool get _sameOwner =>
      mounted &&
      _session.currentUser?.uid == _owner &&
      PilotFeatureAccess.allows(
          uid: _session.currentUser?.uid, email: _session.currentUser?.email);

  Future<Map<String, dynamic>> _query(
      String script, Map<String, dynamic> data) async {
    if (!_sameOwner) throw StateError('A conta mudou.');
    if (widget.query != null) return widget.query!(script, data);
    final credentials = await EdeskCredentialsService().ler();
    if (credentials == null) {
      throw StateError('Configure suas credenciais E-Desk antes de buscar.');
    }
    final url = await edeskEndpointSettings.currentUrl();
    if (!_sameOwner) throw StateError('A conta mudou.');
    final result = await EdeskWebClient(apiUrl: url).execute(
        requestJson: jsonEncode({...data, 'edeskCredenciais': credentials}),
        enviar: false,
        script: script);
    if (!result.confirmed) throw StateError(result.message);
    return Map<String, dynamic>.from(jsonDecode(result.responseBody) as Map);
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _rows = [];
      _message =
          'Consultando a Minha Grid. Aguarde o login e a leitura no computador da integração…';
    });
    try {
      final receipt = await _query('edesk_recebidos.py', {});
      if (!mounted || !_sameOwner) return;
      final grouped = <String, Map<String, dynamic>>{};
      for (final raw in receipt['rows'] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final number = row['solicitacao']?.toString() ?? '';
        if (!RegExp(r'^\d+$').hasMatch(number)) continue;
        final item =
            grouped.putIfAbsent(number, () => {...row, 'works': <String>{}});
        final work = row['idTrabalho']?.toString() ?? '';
        if (RegExp(r'^\d+$').hasMatch(work)) {
          (item['works'] as Set<String>).add(work);
        }
      }
      setState(() {
        _rows = grouped.values.toList();
        _message = receipt['complete'] == true
            ? '${_rows.length} solicitação(ões) encontradas. Confira os dados antes de cadastrar.'
            : 'Busca parcial: ${receipt['reason'] ?? 'parte da grade não foi reconhecida'}. Os resultados abaixo não representam necessariamente todos os trabalhos.';
      });
    } catch (error) {
      if (_sameOwner) {
        setState(() => _message = error is StateError
            ? error.message.toString()
            : 'Não foi possível consultar os trabalhos. Confira a integração.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> row) async {
    if (_busy || !_sameOwner) return;
    setState(() {
      _busy = true;
      _message =
          'Carregando os trabalhos da solicitação ${row['solicitacao']}…';
    });
    try {
      final receipt = await _query('edesk_conferencia.py', {
        'requireWorkEnumeration': (row['works'] as Set<String>).isEmpty,
        'solicitacoes': [
          {
            'solicitacao': row['solicitacao'],
            'trabalhos': (row['works'] as Set<String>).toList()
          }
        ]
      });
      final types = widget.loadTypes != null
          ? await widget.loadTypes!()
          : (await FirebaseService().getWorkFormats())
              .map((f) => f.name)
              .toList();
      if (!mounted || !_sameOwner) return;
      final details = (receipt['rows'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      if (details.isEmpty) {
        throw StateError(
            'Nenhum trabalho foi encontrado nesta solicitação. Nenhum cadastro foi realizado.');
      }
      if (details.any((detail) =>
          detail['solicitacao']?.toString() != row['solicitacao'])) {
        throw StateError(
            'A consulta retornou outra solicitação. Nenhum cadastro foi realizado.');
      }
      final failed = details.where((detail) =>
          detail['error'] != null ||
          !RegExp(r'^\d+$').hasMatch(detail['idTrabalho']?.toString() ?? ''));
      if (failed.isNotEmpty) {
        throw StateError(
            '${failed.first['error'] ?? 'A consulta não identificou os números reais das etapas.'} '
            'Não foi possível importar as etapas. Nenhum cadastro foi realizado.');
      }
      final existing =
          await (widget.loadExisting?.call(row['solicitacao'] as String) ??
              ReceivedWorkStore().loadExisting(row['solicitacao'] as String));
      if (!mounted || !_sameOwner) return;
      setState(() => _busy = false);
      final added = await showDialog<int>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ReceivedWorkReview(
              summary: row,
              details: details,
              types: types,
              existing: existing,
              auth: widget.auth,
              importProject: widget.importProject));
      if (!mounted || !_sameOwner) return;
      if (added != null) {
        setState(() {
          _imported.add(row['solicitacao'] as String);
          _message = added == 0
              ? 'Nenhuma etapa nova: os trabalhos já estavam cadastrados.'
              : '$added trabalho(s) cadastrados no app. Nenhuma alteração foi feita no E-Desk.';
        });
      }
    } catch (error) {
      if (_sameOwner) {
        setState(() => _message = error is StateError
            ? error.message.toString()
            : 'Não foi possível carregar os detalhes. Nenhum cadastro foi realizado.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchById() async {
    if (_busy) return;
    final number = _requestId.text.trim();
    if (!RegExp(r'^\d+$').hasMatch(number)) {
      setState(
          () => _message = 'Informe apenas os números do ID da solicitação.');
      return;
    }
    await _review({'solicitacao': number, 'works': <String>{}});
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Dialog(
          child: SizedBox(
              width: 950,
              height: MediaQuery.sizeOf(context).height * .85,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            widget.importById
                                ? 'Importar do E-Desk pelo ID'
                                : 'Trabalhos recebidos',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(widget.importById
                            ? 'Busque a solicitação e confira as etapas, horas e dados do projeto antes de cadastrar. A integração local precisa estar iniciada.'
                            : 'E-Desk → app · Minha Grid da sua conta · Piloto com conferência antes de cadastrar. A integração local precisa estar iniciada.'),
                        if (widget.importById) ...[
                          const SizedBox(height: 16),
                          TextField(
                              controller: _requestId,
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'ID da solicitação',
                                  hintText: 'Ex.: 2265173'),
                              onSubmitted: (_) => _searchById()),
                        ],
                        const SizedBox(height: 12),
                        SelectableText(_message),
                        const SizedBox(height: 12),
                        if (_busy) const LinearProgressIndicator(),
                        Expanded(
                            child: ListView(children: [
                          for (final row in _rows)
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          SizedBox(
                                              width: 480,
                                              child: Text(
                                                  '${row['solicitacao']} · ${row['client'] ?? 'Cliente não identificado'}\n${row['serviceType'] ?? ''} · ${_imported.contains(row['solicitacao']) ? 'Conferência realizada nesta busca' : 'Aguardando conferência'}')),
                                          OutlinedButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _review(row),
                                              child: const Text(
                                                  'Conferir e cadastrar')),
                                        ])))
                        ])),
                        Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            children: [
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Fechar')),
                              FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : widget.importById
                                          ? _searchById
                                          : _search,
                                  icon:
                                      const Icon(Icons.move_to_inbox_outlined),
                                  label: Text(widget.importById
                                      ? 'Buscar no E-Desk'
                                      : 'Buscar na Minha Grid'))
                            ]),
                      ])))));
}

class _StepDraft {
  _StepDraft(Map<String, dynamic> row) {
    id = row['idTrabalho']?.toString() ?? '';
    final values = Map<String, dynamic>.from(row['values'] as Map? ?? {});
    name.text = values['name']?.toString() ?? '';
    hours.text = values['estimatedHours']?.toString() ?? '';
    start = values['start']?.toString() ?? '';
    end = values['end']?.toString() ?? '';
    error = row['error']?.toString();
    selected = error == null;
  }
  late final String id, start, end;
  late final String? error;
  late bool selected;
  bool existing = false;
  final name = TextEditingController(), hours = TextEditingController();
  void dispose() {
    name.dispose();
    hours.dispose();
  }

  Map<String, String> get data => {
        'id': id,
        'name': name.text,
        'hours': hours.text,
        'start': start,
        'end': end
      };
}

class ReceivedWorkReview extends StatefulWidget {
  const ReceivedWorkReview(
      {super.key,
      required this.summary,
      required this.details,
      required this.types,
      this.existing,
      this.auth,
      this.importProject});
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> details;
  final List<String> types;
  final ProjectModel? existing;
  final FirebaseAuth? auth;
  final Future<int> Function(ProjectModel)? importProject;
  @override
  State<ReceivedWorkReview> createState() => _ReceivedReviewState();
}

class _ReceivedReviewState extends State<ReceivedWorkReview> {
  FirebaseAuth get _session => widget.auth ?? FirebaseAuth.instance;
  final _client = TextEditingController(),
      _type = TextEditingController(),
      _leader = TextEditingController();
  late final List<_StepDraft> _steps;
  late final String? _owner;
  StreamSubscription<User?>? _auth;
  DateTime _date = DateTime.now();
  String _hourType = 'Hs Cobradas', _error = '';
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _owner = _session.currentUser?.uid;
    _auth = _session.authStateChanges().listen((u) {
      if (u?.uid != _owner && mounted) _closeReceivedRoute(context);
    });
    final first =
        widget.details.map((r) => r['values']).whereType<Map>().firstOrNull ??
            {};
    String pick(List<Object?> values) => values
        .map((v) => v?.toString().trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    _client.text = pick(
        [widget.existing?.client, widget.summary['client'], first['client']]);
    _type.text = pick([
      widget.existing?.serviceType,
      widget.summary['serviceType'],
      first['serviceType']
    ]);
    _leader.text = pick(
        [widget.existing?.leader, widget.summary['leader'], first['leader']]);
    _steps = widget.details.map(_StepDraft.new).toList();
    for (final step in _steps) {
      step.existing = widget.existing?.subTasks?.any((task) =>
              task.edeskWorkNumber == step.id &&
              (task.edeskSolicitacao?.trim().isNotEmpty == true
                      ? task.edeskSolicitacao
                      : widget.existing!.id) ==
                  widget.summary['solicitacao']) ==
          true;
      if (step.existing) step.selected = false;
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _client.dispose();
    _type.dispose();
    _leader.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = '');
    try {
      if (widget.existing == null) {
        final known = widget.types
            .where((type) =>
                type.trim().toLowerCase() == _type.text.trim().toLowerCase())
            .firstOrNull;
        if (known == null) {
          throw const FormatException(
              'Selecione um tipo de serviço cadastrado usando as opções abaixo do campo.');
        }
        _type.text = known;
      }
      final project = receivedProject(
          request: widget.summary['solicitacao'] as String,
          client: _client.text,
          type: _type.text,
          leader: _leader.text,
          receivedAt: _date,
          hourType: _hourType,
          requireMetadata: widget.existing == null,
          steps: _steps.where((s) => s.selected).map((s) => s.data).toList());
      setState(() => _saving = true);
      final count = widget.importProject == null
          ? await ReceivedWorkStore()
              .import(project, expectedExisting: widget.existing != null)
          : await widget.importProject!(project);
      if (mounted && _session.currentUser?.uid == _owner) {
        Navigator.pop(context, count);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message
            : error is StateError
                ? error.message.toString()
                : 'Não foi possível confirmar o cadastro. Você pode conferir e tentar novamente; o controle de duplicidade será mantido.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Dialog(
          child: SizedBox(
              width: 950,
              height: MediaQuery.sizeOf(context).height * .9,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            'Conferir cadastro · ${widget.summary['solicitacao']}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text(
                            'Preencha os campos não identificados. Em projetos existentes, somente etapas novas serão adicionadas; cliente, tipo, líder e demais dados atuais serão preservados. O status das novas etapas será Inicial.'),
                        const SizedBox(height: 10),
                        Expanded(
                            child: SingleChildScrollView(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                              TextField(
                                  controller: _client,
                                  enabled: !_saving && widget.existing == null,
                                  decoration: const InputDecoration(
                                      labelText: 'Cliente *')),
                              TextField(
                                  controller: _type,
                                  enabled: !_saving && widget.existing == null,
                                  decoration: const InputDecoration(
                                      labelText: 'Tipo de serviço *')),
                              Wrap(spacing: 8, children: [
                                for (final type in widget.types)
                                  ActionChip(
                                      label: Text(type),
                                      onPressed: _saving ||
                                              widget.existing != null
                                          ? null
                                          : () =>
                                              setState(() => _type.text = type))
                              ]),
                              TextField(
                                  controller: _leader,
                                  enabled: !_saving && widget.existing == null,
                                  decoration: const InputDecoration(
                                      labelText: 'Líder *')),
                              TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () async {
                                          final date = await showDatePicker(
                                              context: context,
                                              initialDate: _date,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100));
                                          if (date != null && mounted) {
                                            setState(() => _date = date);
                                          }
                                        },
                                  child: Text(
                                      'Data de recebimento: ${auditDate(_date)}')),
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _hourType,
                                  decoration: const InputDecoration(
                                      labelText: 'Tipo de horas'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'Hs Cobradas',
                                        child: Text('Hs Cobradas')),
                                    DropdownMenuItem(
                                        value: 'Hs Não Cobradas',
                                        child: Text('Hs Não Cobradas'))
                                  ],
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _hourType = v!)),
                              const SizedBox(height: 12),
                              const Text(
                                  'Selecione as etapas e confira as horas previstas (HH:mm).'),
                              for (final step in _steps)
                                Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              CheckboxListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(
                                                      'Trabalho ${step.id}'),
                                                  subtitle: step.existing
                                                      ? const Text(
                                                          'Já cadastrado no app')
                                                      : step.error == null
                                                          ? null
                                                          : Text(step.error!),
                                                  value: step.selected,
                                                  onChanged: _saving ||
                                                          step.existing ||
                                                          step.error != null
                                                      ? null
                                                      : (value) => setState(
                                                          () => step.selected =
                                                              value == true)),
                                              TextField(
                                                  controller: step.name,
                                                  enabled: !_saving &&
                                                      step.selected,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Nome da etapa *')),
                                              TextField(
                                                  controller: step.hours,
                                                  enabled: !_saving &&
                                                      step.selected,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Horas previstas *',
                                                          hintText: '00:00')),
                                              Text(
                                                  'Início previsto: ${receivedDate(step.start) == null ? 'não identificado' : step.start} · Fim previsto: ${receivedDate(step.end) == null ? 'não identificado' : step.end}'),
                                            ]))),
                              if (_error.isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: SelectableText(_error)),
                            ]))),
                        if (_saving) const LinearProgressIndicator(),
                        Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            children: [
                              TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Cancelar')),
                              FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Cadastrar no app'))
                            ]),
                      ])))));
}
