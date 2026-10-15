import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';
import 'package:gerenciador_horas/data/services/native_local_files_service.dart';
import 'package:gerenciador_horas/data/services/file_download.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'email_document.dart';
import 'email_workbook.dart';
import 'email_draft_store.dart';
import 'products_image_field.dart';
import 'email_body_preview.dart';
import 'email_recipient_fields.dart';

class ProjectEmailModal extends StatefulWidget {
  final ProjectModel project;
  final EmailDraftStore? store;
  final Future<Uint8List?> Function()? workbookLoader;
  const ProjectEmailModal(
      {super.key, required this.project, this.store, this.workbookLoader});
  static Future<void> show(BuildContext context, ProjectModel project) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ProjectEmailModal(project: project));
  @override
  State<ProjectEmailModal> createState() => _ProjectEmailModalState();
}

class _ProjectEmailModalState extends State<ProjectEmailModal> {
  late final String? _uid;
  late final EmailDraftStore _store;
  ProjectEmailKind _kind = ProjectEmailKind.initial;
  final _fields = <String, TextEditingController>{};
  final _subject = TextEditingController(), _body = TextEditingController();
  final _contacts = <EmailContact>[];
  final _projectContacts = <EmailContact>[];
  bool _projectContactsLoaded = false;
  final _recipientKey = GlobalKey<EmailRecipientFieldsState>();
  final _attachments = <EmailAttachment>[];
  Uint8List? _productsImage;
  final _cache = <ProjectEmailKind, Map<String, dynamic>>{};
  final _saved = <ProjectEmailKind, String>{};
  String _subjectTemplate = '', _bodyTemplate = '', _message = '';
  String _localStatus = '';
  String _lastRecovery = '';
  String _summaryInMessage = '';
  bool _closing = false, _allowClose = false, _discardOnClose = false;
  String get _recoveryKey => 'email.${widget.project.id}.${_kind.name}';

  void _recoverLocally() {
    if (_discardOnClose || !_ready || _busy || !_sameAccount) return;
    final snapshot = _snapshot();
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastRecovery) return;
    _lastRecovery = encoded;
    final saved = RecoverableDraft.save(_uid, _recoveryKey, snapshot);
    _localStatus = saved
        ? 'Cópia de recuperação salva neste dispositivo.'
        : 'Não foi possível salvar a cópia local. Use Salvar neste projeto.';
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _recoverLocally();
  }

  bool _busy = true,
      _ready = false,
      _customBody = false,
      _customSubject = false;
  bool get _sameAccount => _uid != null && _store.currentUserId == _uid;
  @override
  void initState() {
    super.initState();
    _store = widget.store ?? FirebaseEmailDraftStore();
    _uid = _store.currentUserId;
    for (final field in emailFieldLabels.keys) {
      _fields[field] = TextEditingController();
    }
    _load();
  }

  Map<String, String> get _values => {
        for (final entry in _fields.entries) entry.key: entry.value.text,
        if (_productsImage != null) 'produtos': productsImageMarker,
        'equipe': _contacts
            .where((c) => c.group == 'Cyncly')
            .map((c) => '${c.role}: ${c.name}')
            .join('\n'),
      };
  Map<String, dynamic> _snapshot() => {
        'fields': _values,
        'contacts': _contacts.map((c) => c.toJson()).toList(),
        'body': _customBody ? _body.text : null,
        'subject': _customSubject ? _subject.text : null,
        'productsImage':
            _productsImage == null ? null : base64Encode(_productsImage!),
        'recipientsConfigured': true,
      };
  void _render() {
    if (!_customSubject) {
      _subject.text = renderEmailTemplate(_subjectTemplate, _values);
    }
    if (!_customBody) _body.text = renderEmailTemplate(_bodyTemplate, _values);
    if (_kind == ProjectEmailKind.internal) {
      _body.text = emailBodyWithSummary(_body.text, _fields['resumo']!.text,
          previousSummary: _summaryInMessage);
      _summaryInMessage = _fields['resumo']!.text;
    }
    if (_productsImage != null && _kind == ProjectEmailKind.internal) {
      _body.text = emailBodyWithProductsImage(_body.text);
    }
    _body.text = cleanRemovedEmailFields(_body.text, _kind,
        consultantPhone: _fields['telefone_consultor']!.text);
  }

  Future<void> _load() async {
    _ready = false;
    _localStatus = '';
    setState(() => _busy = true);
    try {
      if (!_sameAccount) throw StateError('Entre novamente na sua conta.');
      var recovery = RecoverableDraft.read(_uid, _recoveryKey);
      Map<String, dynamic>? template, remote;
      try {
        template = await _store.loadTemplate(_uid!, _kind);
      } catch (_) {
        if (recovery == null && _cache[_kind] == null) rethrow;
      }
      try {
        remote = await _store.loadDraft(_uid!, widget.project.id, _kind);
      } catch (_) {
        if (recovery == null && _cache[_kind] == null) rethrow;
      }
      final remoteDate = remote?['updatedAt'];
      final recoveryDate =
          DateTime.tryParse(recovery?['savedAt']?.toString() ?? '');
      if (remoteDate is Timestamp &&
          recoveryDate != null &&
          remoteDate.toDate().isAfter(recoveryDate)) {
        RecoverableDraft.clear(_uid, _recoveryKey);
        recovery = null;
      }
      var draft = _cache[_kind] ?? recovery ?? remote;
      if (recovery != null)
        _localStatus =
            'Rascunho recuperado neste dispositivo. Revise os destinatários e selecione os anexos novamente.';
      if (draft == null) {
        Map<String, dynamic>? shared =
            _cache.isEmpty ? null : _cache.values.last;
        if (shared == null) {
          for (final other
              in ProjectEmailKind.values.where((kind) => kind != _kind)) {
            shared = await _store.loadDraft(_uid!, widget.project.id, other);
            if (shared != null) break;
          }
        }
        if (shared != null) {
          draft = {
            'fields': shared['fields'],
            'productsImage': shared['productsImage'],
            'contacts': [
              for (final c in shared['contacts'] as List? ?? [])
                {...Map<String, dynamic>.from(c), 'destination': 'Não incluir'}
            ]
          };
        }
      }
      if (!_projectContactsLoaded) {
        final sources = await Future.wait([
          for (final other in ProjectEmailKind.values.where((kind) => kind != _kind))
            () async {
              try {
                return _cache[other] ?? await _store.loadDraft(_uid!, widget.project.id, other);
              } catch (_) {
                return null;
              }
            }(),
        ]);
        if (!mounted || !_sameAccount) return;
        for (final source in sources) {
          mergeAvailableEmailContacts(_projectContacts, [
            for (final item in source?['contacts'] as List? ?? [])
              EmailContact.fromJson(Map<String, dynamic>.from(item)),
          ]);
        }
        _projectContactsLoaded = true;
      }
      if (!mounted || !_sameAccount) return;
      _subjectTemplate =
          template?['subject'] as String? ?? defaultEmailSubject(_kind);
      _bodyTemplate = cleanRemovedEmailFields(
          template?['body'] as String? ?? defaultEmailBody(_kind), _kind);
      for (final controller in _fields.values) {
        controller.clear();
      }
      _fields['cliente']!.text = widget.project.client;
      _fields['razao_social']!.text = widget.project.client;
      _fields['solicitacao']!.text = widget.project.id;
      _fields['servico']!.text = widget.project.serviceType;
      _contacts.clear();
      _summaryInMessage = '';
      _productsImage = null;
      if (draft != null) {
        final encodedImage = draft['productsImage'];
        if (encodedImage is String && encodedImage.length <= 700000) {
          try {
            final bytes = base64Decode(encodedImage);
            if (bytes.isNotEmpty && bytes.length <= 512 * 1024)
              _productsImage = bytes;
          } catch (_) {
            /* A damaged image must not prevent restoring the text. */
          }
        }
        final values = draft['fields'] as Map? ?? {};
        for (final entry in _fields.entries) {
          if (values[entry.key] is String) entry.value.text = values[entry.key];
        }
        for (final contact in draft['contacts'] as List? ?? []) {
          _contacts
              .add(EmailContact.fromJson(Map<String, dynamic>.from(contact)));
        }
      }
      mergeAvailableEmailContacts(_projectContacts, _contacts);
      mergeAvailableEmailContacts(_contacts, _projectContacts);
      if (draft?['recipientsConfigured'] != true &&
          !_contacts.any((c) => ['Para', 'Cc'].contains(c.destination))) {
        selectModelRecipients(_contacts, _kind);
      }
      _customBody = draft?['body'] is String;
      _customSubject = draft?['subject'] is String;
      if (_customBody) _body.text = draft!['body'];
      if (_customSubject) _subject.text = draft!['subject'];
      _render();
      _lastRecovery = jsonEncode(_snapshot());
      _ready = true;
      _saved.putIfAbsent(_kind, () => jsonEncode(_snapshot()));
      _message =
          'Destinatários precisam ser revisados. Anexos não são guardados no rascunho.';
    } catch (error) {
      _ready = false;
      if (mounted) {
        _message =
            recoveryError(error, operation: 'carregar os modelos e o rascunho');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_recipientKey.currentState?.commitPending() ?? true)) return;
    setState(() => _busy = true);
    try {
      if (!_sameAccount) {
        throw StateError('A conta mudou. Feche e abra novamente.');
      }
      final snapshot = _snapshot();
      if (utf8.encode(jsonEncode(snapshot)).length > 900 * 1024) {
        throw const FormatException(
            'O rascunho ficou grande demais. Use um print menor e reduza o texto.');
      }
      await _store.saveDraft(_uid!, widget.project.id, _kind, snapshot);
      if (!mounted || !_sameAccount) return;
      _saved[_kind] = jsonEncode(_snapshot());
      setState(
          () => _message = 'Rascunho salvo somente neste projeto e modelo.');
      RecoverableDraft.clear(_uid, _recoveryKey);
      _lastRecovery = jsonEncode(_snapshot());
      _localStatus = 'Salvo na sua conta neste projeto e modelo.';
    } catch (error) {
      if (mounted) {
        setState(() =>
            _message = recoveryError(error, operation: 'salvar o rascunho'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import({bool linked = true}) async {
    setState(() => _busy = true);
    try {
      Uint8List bytes;
      final reference = widget.project.excelLink?.trim() ?? '';
      if (widget.workbookLoader != null) {
        final selected = await widget.workbookLoader!();
        if (selected == null) return;
        bytes = selected;
      } else if (linked &&
          reference.isNotEmpty &&
          !reference.startsWith('http')) {
        bytes = BrowserLocalFiles.isReference(reference)
            ? await BrowserLocalFiles.read(reference)
            : await NativeLocalFiles.read(reference);
      } else {
        final selection = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['xlsx', 'xlsm'],
            withData: true);
        if (selection == null) return;
        bytes = selection.files.single.bytes ??
            (throw const FormatException(
                'Não foi possível ler o arquivo selecionado.'));
      }
      final parsed = readEmailWorkbook(bytes);
      if (!mounted || !_sameAccount) return;
      var regenerateMessage = true;
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Importar dados da planilha?'),
                  content: StatefulBuilder(
                      builder: (context, update) => SizedBox(
                          width: 540,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(
                                    'Foram encontrados ${parsed.contacts.length} contatos e ${parsed.fields.length} campos. Os dados preencherão os campos correspondentes do modelo. O print de Produtos adquiridos será preservado. Valores vazios ou com #...# serão ignorados. Se não houver contatos na planilha, os atuais serão mantidos. Revise depois os destinatários Para/Cc.'),
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: regenerateMessage,
                                    title: const Text(
                                        'Regerar assunto e mensagem conforme o modelo'),
                                    subtitle: const Text(
                                        'Usa os dados atualizados da planilha. Substitui edições manuais do assunto e da mensagem.'),
                                    onChanged: (value) => update(() =>
                                        regenerateMessage = value ?? true)),
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Importar'))
                  ]));
      if (accepted != true || !mounted || !_sameAccount) return;
      setState(() {
        if (parsed.contacts.isNotEmpty) {
          _projectContacts.clear();
          mergeAvailableEmailContacts(_projectContacts, parsed.contacts);
          _contacts
            ..clear()
            ..addAll(parsed.contacts);
          selectModelRecipients(_contacts, _kind);
        }
        for (final field in parsed.fields.entries) {
          _fields[field.key]?.text = field.value;
        }
        if (regenerateMessage) {
          _customBody = false;
          _customSubject = false;
        }
        _render();
        _message =
            '${parsed.contacts.length} contatos e ${parsed.fields.length} campos importados. Destinatários preenchidos conforme o modelo. Revise Para e Cc antes de gerar.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            'Não foi possível importar. Verifique a aba Informações de entrada e a integração local, ou use Selecionar planilha (.xlsx/.xlsm).');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: true);
      if (result == null || !mounted || !_sameAccount) return;
      final selected = [
        for (final file in result.files)
          if (file.bytes != null) EmailAttachment(file.name, file.bytes!)
      ];
      if (selected.fold<int>(0, (s, a) => s + a.bytes.length) +
              _attachments.fold<int>(0, (s, a) => s + a.bytes.length) >
          20 * 1024 * 1024) {
        throw const FormatException('Use até 20 MB de anexos por e-mail.');
      }
      setState(() => _attachments.addAll(selected));
    } catch (error) {
      if (mounted) {
        setState(() =>
            _message = 'Não foi possível adicionar. Use até 20 MB de anexos.');
      }
    }
  }

  Future<void> _generate() async {
    if (!(_recipientKey.currentState?.commitPending() ?? true)) {
      await _generationError('Revise os e-mails digitados nos campos Para e Cc.');
      return;
    }
    try {
      if (!_sameAccount) {
        throw StateError('A conta mudou. Feche e abra novamente.');
      }
      if (_kind == ProjectEmailKind.internal) {
        _body.text = emailBodyWithSummary(_body.text, _fields['resumo']!.text,
            previousSummary: _summaryInMessage);
        _summaryInMessage = _fields['resumo']!.text;
      }
      if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
        throw const FormatException('Preencha assunto e mensagem.');
      }
      final required = [
        'cliente',
        'solicitacao',
        'consultor',
        if (_kind == ProjectEmailKind.initial) ...[
          'sistema',
        ],
        if (_kind == ProjectEmailKind.finalization) ...[
          'data_finalizacao',
          'er',
          'email_er'
        ],
        if (_kind == ProjectEmailKind.internal) ...[
          'sistema',
          'data_recebimento',
          'data_finalizacao'
        ]
      ];
      final missing = required.where((key) => _fields[key]!.text.trim().isEmpty);
      if (missing.isNotEmpty) {
        throw FormatException(
            'Preencha estes campos para gerar o e-mail:\n\n${missing.map((key) => '• ${emailFieldLabels[key]}').join('\n')}');
      }
      if (RegExp(r'\{[a-z_]+\}').hasMatch('${_subject.text}\n${_body.text}')) {
        throw const FormatException('Preencha os campos pendentes do modelo.');
      }
      final signature = await rootBundle.load('assets/images/email_signature_cyncly.jpg');
      final signatureIcons = <String, Uint8List>{};
      for (final key in ['mail', 'phone', 'web']) {
        final data = await rootBundle.load('assets/images/email_signature_$key.png');
        signatureIcons[key] = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      if (!mounted || !_sameAccount) return;
      final bytes = buildEmailDraft(
          subject: _subject.text,
          body: _body.text,
          contacts: _contacts,
          attachments: _attachments,
          signatureImage: signature.buffer.asUint8List(signature.offsetInBytes, signature.lengthInBytes),
          signatureName: _fields['consultor']!.text.trim(),
          signatureEmail: _fields['email_consultor']!.text.trim(),
          signaturePhone: _fields['telefone_consultor']!.text.trim().isNotEmpty
              ? _fields['telefone_consultor']!.text.trim()
              : _fields['email_consultor']!.text.trim().toLowerCase() == 'rodrigo.zaparolli@cyncly.com'
                  ? '5430225800' : '',
          signatureIcons: signatureIcons,
          productsImage:
              _kind == ProjectEmailKind.internal ? _productsImage : null);
      final name =
          '${_kind.name}-${widget.project.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.eml';
      final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Gerar rascunho para Outlook?'),
                  content: Text(
                      'Confira os destinatários, o texto e os ${_attachments.length} anexos. O arquivo .eml será gerado para revisão no Outlook; não haverá envio automático.\n\nNo encerramento interno, confira também os dados de acesso incluídos no texto.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Revisar')),
                    FilledButton(
                        onPressed: () {
                          // Start the web download directly in the user click.
                          if (kIsWeb) {
                            try {
                              downloadBytes(fileName: name, bytes: bytes,
                                  mimeType: 'message/rfc822');
                            } catch (error) {
                              Navigator.pop(context, false);
                              _generationError('Não foi possível iniciar o download. Tente novamente e confira as permissões de download do navegador.');
                              return;
                            }
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('Baixar arquivo .eml'))
                  ]));
      if (approved != true || !mounted || !_sameAccount) return;
      if (!kIsWeb) {
        final path = await FilePicker.platform.saveFile(
            fileName: name,
            bytes: [TargetPlatform.android, TargetPlatform.iOS]
                    .contains(defaultTargetPlatform)
                ? bytes
                : null,
            type: FileType.custom,
            allowedExtensions: ['eml']);
        if (path == null) return;
        if (![TargetPlatform.android, TargetPlatform.iOS]
            .contains(defaultTargetPlatform)) {
          await writeLocalBytes(path, bytes);
        }
      }
      if (mounted) {
        setState(() => _message =
            'Arquivo gerado. Abra no Outlook e confira antes de enviar. A edição do .eml depende da versão do Outlook.');
        await showDialog<void>(context: context,
            builder: (context) => AlertDialog(
              title: Text(kIsWeb ? 'Download iniciado' : 'Arquivo salvo'),
              content: Text('$name\n\n${kIsWeb ? 'Pressione Ctrl + J para conferir o download. O navegador pode perguntar onde salvar ou exibir um aviso de bloqueio.' : 'Abra o arquivo salvo no Outlook.'}\n\nO arquivo não abre o Outlook automaticamente e nenhum e-mail foi enviado.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text('Entendi'))],
            ));
      }
    } on FormatException catch (e) {
      await _generationError(e.message);
    } catch (error) {
      await _generationError('Não foi possível gerar o arquivo. ${recoveryError(error, operation: 'gerar o e-mail')}');
    }
  }

  Future<void> _generationError(String message) async {
    if (!mounted) return;
    setState(() => _message = message);
    await showDialog<void>(context: context,
        builder: (context) => AlertDialog(
          title: const Text('O e-mail ainda não foi gerado'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Corrigir dados'))],
        ));
  }

  Future<void> _editTemplate() async {
    final subject = TextEditingController(text: _subjectTemplate),
        body = TextEditingController(text: _bodyTemplate);
    final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Modelo padrão — ${_kind.label}'),
                content: SizedBox(
                    width: 650,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Aplica-se aos seus próximos rascunhos. Use campos como {cliente}, {solicitacao}, {consultor} e {equipe}. Os rascunhos com texto editado serão preservados.'),
                      const SizedBox(height: 12),
                      ExpansionTile(
                          title: const Text('Campos disponíveis no modelo'),
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: SelectableText(emailFieldLabels.entries
                                    .map((entry) =>
                                        '${entry.value}: {${entry.key}}')
                                    .join('\n')))
                          ]),
                      TextField(
                          controller: subject,
                          decoration: const InputDecoration(
                              labelText: 'Assunto padrão')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: body,
                          maxLines: 14,
                          decoration:
                              const InputDecoration(labelText: 'Texto padrão'))
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Salvar modelo'))
                ]));
    final newSubject = subject.text,
        newBody = cleanRemovedEmailFields(body.text, _kind);
    // Dialog closing animation still uses its controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    subject.dispose();
    body.dispose();
    if (result != true || !mounted || !_sameAccount) return;
    setState(() => _busy = true);
    try {
      await _store
          .saveTemplate(_uid!, _kind, {'subject': newSubject, 'body': newBody});
      if (mounted && _sameAccount) {
        setState(() {
          _subjectTemplate = newSubject;
          _bodyTemplate = newBody;
          _render();
          _message = 'Modelo padrão atualizado para sua conta.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Não foi possível salvar o modelo padrão.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _panel(Widget child) => Container(
      decoration: AppVisuals.card,
      padding: const EdgeInsets.all(16),
      child: Material(type: MaterialType.transparency, child: child));
  Future<void> _close() async {
    if (_closing || _busy) return;
    _closing = true;
    try {
      final keep = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
                  title: const Text('Manter as alterações?'),
                  content: const Text(
                      'Manter guarda os dados, mensagens e print neste dispositivo para continuar depois. Descartar remove as alterações não salvas; o que já foi salvo no projeto permanece. Os anexos precisam ser selecionados novamente.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Continuar editando')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Descartar e fechar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Manter e fechar'))
                  ]));
      if (keep == null || !mounted) return;
      if (keep && !(_recipientKey.currentState?.commitPending() ?? true)) return;
      final snapshots = {..._cache, _kind: _snapshot()};
      if (keep) {
        if (!_sameAccount || !snapshots.entries.every((entry) =>
            RecoverableDraft.save(_uid,
                'email.${widget.project.id}.${entry.key.name}', entry.value))) {
          setState(() => _message =
              'Não foi possível manter o rascunho neste dispositivo. Salve no projeto antes de fechar.');
          return;
        }
      } else {
        _discardOnClose = true;
        for (final kind in snapshots.keys) {
          RecoverableDraft.clear(
              _uid, 'email.${widget.project.id}.${kind.name}');
        }
      }
      setState(() => _allowClose = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      _closing = false;
    }
  }

  Widget _dataPanel() =>
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dados e destinatários',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final key in [
          'cliente',
          'solicitacao',
          'servico',
          if (_kind == ProjectEmailKind.initial) ...[
            'sistema',
            'consultor',
            'email_consultor',
          ],
          if (_kind == ProjectEmailKind.finalization) ...[
            'data_finalizacao',
            'er',
            'email_er',
            'consultor',
            'email_consultor',
          ],
          if (_kind == ProjectEmailKind.internal) ...[
            'sistema',
            'data_recebimento',
            'data_finalizacao',
            'materiais',
            'liberacao',
            'produtos',
            'resumo',
            'consultor',
            'email_consultor',
          ]
        ])
          if (key == 'produtos')
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProductsImageField(
                    image: _productsImage,
                    enabled: _ready && !_busy,
                    onChanged: (image) => setState(() {
                          _productsImage = image;
                          _fields['produtos']!.clear();
                          if (image == null && _customBody) {
                            _body.text =
                                _body.text.replaceAll(productsImageMarker, '');
                          }
                          _render();
                        })))
          else
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                    controller: _fields[key],
                    maxLines: ['produtos', 'resumo'].contains(key) ? 3 : 1,
                    decoration:
                        InputDecoration(labelText: emailFieldLabels[key]),
                    onChanged: (_) => setState(_render))),
        if (_kind == ProjectEmailKind.internal)
          ExpansionTile(
              title: const Text('Dados do sistema e do cliente'),
              children: [
                for (final key in [
                  'biblioteca',
                  'cnpj',
                  'senha_dimensoes',
                  'senha_orcamentos',
                  'senha_margens',
                  'razao_social',
                  'nome_fantasia',
                  'proprietario',
                  'email_cliente',
                  'telefone_cliente',
                  'responsavel_tecnico',
                  'email_tecnico',
                  'telefone_tecnico',
                  'cpf_proprietario',
                  'cpf_tecnico',
                  'nome_resumido_sistema',
                  'id_sistema',
                  'ns',
                  'versao',
                  'assinatura_proposta',
                  'telefone_cliente_secundario',
                  'email_portal',
                  'ie',
                  'cep',
                  'estado',
                  'cidade',
                  'bairro',
                  'rua',
                  'complemento',
                  'numero',
                  'site_prices',
                  'id_prices',
                  'usuario_prices',
                  'senha_prices'
                ])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                          controller: _fields[key],
                          decoration:
                              InputDecoration(labelText: emailFieldLabels[key]),
                          onChanged: (_) => setState(_render)))
              ]),
        const Divider(),
        const Text('Contatos — selecione Para ou Cc',
            style: TextStyle(fontWeight: FontWeight.bold)),
        if (_contacts.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Importe da planilha ou adicione os contatos.')),
        for (final c in _contacts)
          Padding(
              key: ObjectKey(c),
              padding: const EdgeInsets.only(top: 12),
              child: Column(children: [
                DropdownButtonFormField<String>(
                    initialValue: c.group == 'Cliente' ? 'Cliente' : 'Cyncly',
                    decoration:
                        const InputDecoration(labelText: 'Grupo do contato'),
                    items: ['Cliente', 'Cyncly']
                        .map((group) =>
                            DropdownMenuItem(value: group, child: Text(group)))
                        .toList(),
                    onChanged: (group) => setState(() {
                          c.group = group!;
                          _render();
                        })),
                const SizedBox(height: 8),
                TextFormField(
                    key: ObjectKey(c),
                    initialValue: c.role,
                    decoration:
                        const InputDecoration(labelText: 'Cargo / função'),
                    onChanged: (v) => setState(() {
                          c.role = v;
                          _render();
                        })),
                const SizedBox(height: 8),
                TextFormField(
                    initialValue: c.name,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    onChanged: (v) => setState(() {
                          c.name = v;
                          _render();
                        })),
                const SizedBox(height: 8),
                TextFormField(
                    initialValue: c.email,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    onChanged: (v) => setState(() => c.email = v)),
                Row(children: [
                  Expanded(
                      child: DropdownButton<String>(
                          isExpanded: true,
                          value: ['Para', 'Cc'].contains(c.destination)
                              ? c.destination
                              : 'Não incluir',
                          items: ['Não incluir', 'Para', 'Cc']
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => c.destination = v!))),
                  IconButton(
                      tooltip: 'Remover contato',
                      onPressed: () => setState(() {
                            _contacts.remove(c);
                            _render();
                          }),
                      icon: const Icon(Icons.delete_outline))
                ]),
              ])),
        TextButton.icon(
            onPressed: () => setState(() => _contacts.add(EmailContact())),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Adicionar contato')),
        const Divider(),
        const Text('Anexos', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final a in _attachments)
          Row(children: [
            Expanded(child: Text(a.name)),
            IconButton(
                onPressed: () => setState(() => _attachments.remove(a)),
                icon: const Icon(Icons.close),
                tooltip: 'Remover anexo')
          ]),
        TextButton.icon(
            onPressed: _pickAttachments,
            icon: const Icon(Icons.attach_file),
            label: const Text('Selecionar anexos')),
        const Text(
            'Os arquivos ficam nesta sessão. Ao reabrir, selecione os anexos novamente.',
            style: TextStyle(fontSize: 12)),
      ]));
  Widget _preview() =>
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Prévia do e-mail',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Assunto'),
            onChanged: (_) => setState(() => _customSubject = true)),
        const SizedBox(height: 16),
        if (_kind == ProjectEmailKind.internal && _productsImage != null) ...[
          EmailBodyPreview(body: _body.text, productsImage: _productsImage!),
          const SizedBox(height: 12),
          ExpansionTile(
              title: const Text('Editar mensagem'),
              maintainState: true,
              children: [_messageEditor()]),
        ] else
          _messageEditor(),
        const SizedBox(height: 12),
        Image.asset('assets/images/email_signature_cyncly.jpg',
            key: const ValueKey('email-signature-banner'),
            width: 630, fit: BoxFit.contain),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: '${_subject.text}\n\n${_body.text}'));
                if (mounted) {
                  setState(() => _message = _productsImage != null &&
                          _kind == ProjectEmailKind.internal
                      ? 'Texto copiado. Use Gerar rascunho para Outlook para incluir o print no corpo do e-mail.'
                      : 'Texto copiado. Destinatários e anexos precisam ser adicionados no Outlook.');
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar texto'))
        ]),
        const Text(
            'Revise texto, destinatários e anexos. O rascunho não é enviado automaticamente.',
            style: TextStyle(fontSize: 12)),
      ]));
  Widget _messageEditor() => TextField(
      controller: _body,
      minLines: 20,
      maxLines: null,
      decoration: const InputDecoration(labelText: 'Mensagem — editável'),
      onChanged: (_) => setState(() => _customBody = true));
  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    _recoverLocally();
    return PopScope(
        canPop: _allowClose,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: AppPalette.surface,
        child: SizedBox(
            width: 1380,
            height: MediaQuery.sizeOf(context).height * .92,
            child: Column(children: [
              if (_localStatus.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: Text(_localStatus,
                        style: TextStyle(
                            color: AppPalette.secondary, fontSize: 12))),
              Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Icon(Icons.mail_outline, color: AppPalette.primary),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('E-mails do projeto',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                          Text(
                              '${widget.project.id} • ${widget.project.client} • Enterprise',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)
                        ])),
                    IconButton(
                        onPressed: _close,
                        icon: const Icon(Icons.close),
                        tooltip: 'Fechar')
                  ])),
              if (_busy) const LinearProgressIndicator(),
              const Divider(height: 1),
              Expanded(
                  child: AbsorbPointer(
                      absorbing: _busy || !_ready,
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                EmailRecipientFields(
                                    key: _recipientKey,
                                    contacts: _contacts,
                                    onChanged: () => setState(_render)),
                                const Divider(),

                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final kind in ProjectEmailKind.values)
                                    ChoiceChip(
                                        label: Text(kind.label),
                                        selected: kind == _kind,
                                        onSelected: (_) {
                                          if (kind == _kind) return;
                                          if (!(_recipientKey.currentState?.commitPending() ?? true)) return;
                                          _recoverLocally();
                                          _cache[_kind] = _snapshot();
                                          _attachments.clear();
                                          _kind = kind;
                                          _load();
                                        })
                                ]),
                                const SizedBox(height: 14),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  FilledButton.icon(
                                      onPressed: () => setState(() {
                                            _customBody = false;
                                            _customSubject = false;
                                            _render();
                                            _message =
                                                'Dados carregados no modelo de e-mail. Revise a mensagem; o assunto e o texto foram atualizados conforme os campos preenchidos.';
                                          }),
                                      icon: const Icon(Icons.mail_outline),
                                      label: const Text(
                                          'Carregar dados no modelo')),
                                  OutlinedButton.icon(
                                      onPressed: _import,
                                      icon: const Icon(
                                          Icons.table_chart_outlined),
                                      label: const Text(
                                          'Atualizar da planilha do projeto')),
                                  TextButton(
                                      onPressed: () => _import(linked: false),
                                      child: const Text('Selecionar planilha'))
                                ]),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Text(_message,
                                        style: TextStyle(
                                            color: AppPalette.secondary))),
                                LayoutBuilder(
                                    builder: (context, c) => c.maxWidth >= 900
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                                Expanded(
                                                    flex: 2,
                                                    child: _dataPanel()),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                    flex: 3, child: _preview())
                                              ])
                                        : Column(children: [
                                            _dataPanel(),
                                            const SizedBox(height: 16),
                                            _preview()
                                          ])),
                                const SizedBox(height: 16),
                              ])))),
              const Divider(height: 1),
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(spacing: 10, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: _busy || !_ready ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar neste projeto')),
                    TextButton(
                        onPressed: _busy || !_ready ? null : _editTemplate,
                        child: const Text('Editar modelo padrão')),
                    FilledButton.icon(
                        onPressed: _busy || !_ready ? null : _generate,
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('Gerar e-mail para Outlook'))
                  ])),
            ]))));
  }

  @override
  void dispose() {
    _recoverLocally();
    for (final c in _fields.values) {
      c.dispose();
    }
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }
}
