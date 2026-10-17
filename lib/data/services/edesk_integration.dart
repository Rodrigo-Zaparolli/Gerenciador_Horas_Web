import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'edesk_endpoint.dart';
import 'edesk_extension.dart';
import '../../features/edesk/edesk_central_dialog.dart';
import '../../features/edesk/edesk_comment_preview.dart';
import '../../features/edesk/comment_document_preview.dart';

const edeskApiUrl = defaultEdeskApiUrl;
final appNavigatorKey = GlobalKey<NavigatorState>();
final edeskProgress = ValueNotifier<String>('Abrindo E-Desk…');
final edeskProgressCounts = ValueNotifier<({int completed, int total})>((completed: 0, total: 0));

class EdeskIntegrationApi {
  static Future<String> currentUrl() => urlProvider();
  @visibleForTesting
  static Future<String> Function() urlProvider =
      () => edeskEndpointSettings.currentUrl();
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  @visibleForTesting
  static Future<String?> Function() tokenProvider =
      () async => FirebaseAuth.instance.currentUser?.getIdToken();
  static Future<Map<String, dynamic>> call(String path,
      {Map<String, dynamic>? body,
      bool authenticated = true,
      String? baseUrl}) async {
    final resolvedUrl = baseUrl ?? await urlProvider();
    final host = Uri.parse(resolvedUrl).host;
    if (baseUrl == null && host != '127.0.0.1' && host != 'localhost' && await edeskExtensionAvailable()) {
      final uid = authenticated ? FirebaseAuth.instance.currentUser?.uid : null;
      return edeskExtensionCall(path, body: body, uid: uid);
    }
    final client = clientFactory();
    try {
      final token = authenticated ? await tokenProvider() : null;
      if (authenticated && token == null) {
        throw StateError('Entre novamente na sua conta.');
      }
      final headers = {
        if (token != null) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final base = Uri.parse(normalizeEdeskUrl(resolvedUrl));
      final uri =
          base.resolve('${base.path.replaceFirst(RegExp(r'/+$'), '')}$path');
      final response = await (body == null
              ? client.get(uri, headers: headers)
              : client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw StateError('Resposta inválida da integração.');
      }
      if (response.statusCode != 200) {
        throw StateError(data['message']?.toString() ?? 'Falha na integração.');
      }
      return data;
    } finally {
      client.close();
    }
  }
}

String progressLabel(String? stage) => switch (stage) {
      'opening' => 'Abrindo E-Desk…',
      'login' =>
        'Aguardando login — conclua o acesso na janela do E-Desk no computador que executa a integração.',
      'preparing' => 'Localizando os trabalhos no E-Desk…',
      'sending' => 'Enviando e verificando o registro no E-Desk…',
      'finished' => 'Recebendo o resultado do envio…',
      _ => 'Aguardando a integração…',
    };

Future<void> showIntegrationStatus(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _IntegrationStatusDialog(),
  );
}

class _IntegrationStatusDialog extends StatefulWidget {
  const _IntegrationStatusDialog();
  @override
  State<_IntegrationStatusDialog> createState() =>
      _IntegrationStatusDialogState();
}

class _IntegrationStatusDialogState extends State<_IntegrationStatusDialog> {
  String message = 'Verificando integração…';
  bool checking = false;
  bool connected = false;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() => checking = true);
    try {
      final health =
          await EdeskIntegrationApi.call('/healthz', authenticated: false);
      if (health['mode'] == 'central')
        await EdeskIntegrationApi.call('/api/edesk/session');
      if (!mounted) return;
      connected = health['service'] == 'gerenciador-horas-edesk' &&
          health['status'] == 'ok' &&
          health['mode'] != 'files-only';
      message = health['mode'] == 'files-only'
          ? 'A abertura de arquivos está conectada, mas não envia horas ao E-Desk. Instale e ative a extensão E-Desk neste navegador e recarregue o app.'
          : !connected
              ? 'Serviço de integração não reconhecido.'
              : health['busy'] == true
                  ? 'Integração conectada. Há um envio em andamento.'
                  : health['mode'] == 'extension'
                      ? 'Extensão conectada. Os envios usam o E-Desk neste navegador, sem central.'
                      : 'Integração conectada e pronta para enviar.';
    } catch (_) {
      if (!mounted) return;
      connected = false;
      message =
          'Integração desconectada. Se usa a central, verifique se ela está ligada, '
          'se esta conta está autorizada e se o navegador tem acesso à rede local. '
          'Para enviar sem central, instale a extensão E-Desk neste navegador e recarregue o app.';
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Integração E-Desk'),
        content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(connected ? Icons.check_circle_outline : Icons.link_off,
                  color: connected ? Colors.greenAccent : Colors.orangeAccent,
                  size: 36),
              const SizedBox(height: 16),
              Text(message),
              if (checking)
                const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator()),
            ])),
        actions: [
          TextButton(
              onPressed: () => launchUrl(
                  Uri.parse(
                      'https://gerenciador-horas.web.app/instalar-extensao.html'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Instalar extensão')),
          TextButton(
              onPressed: checking
                  ? null
                  : () async {
                      await showDialog<void>(
                          context: context,
                          builder: (_) => const EdeskCentralDialog());
                      if (mounted) await check();
                    },
              child: const Text('Configurar central')),
          TextButton(
              onPressed: checking ? null : check,
              child: const Text('Verificar novamente')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'))
        ],
      );
}

class EdeskReviewDecision {
  final bool send;
  final bool retryUncertain;
  const EdeskReviewDecision(this.send, {this.retryUncertain = false});
}

List<String> edeskReviewLines(Map<String, dynamic> data, String script) {
  if (script == 'edesk_horas.py') {
    return [
      for (final work in data['trabalhos'] as List? ?? [])
        for (final hour in work['horas'] as List? ?? [])
          '${work['solicitacao']}/${work['idTrabalho']} · ${hour['data']} · '
              '${hour['inicio']}–${hour['fim']}\n'
              '${hour['tarefa'] ?? ''}\n${hour['descricao'] ?? hour['descritivo'] ?? ''}'
    ];
  }
  if (script == 'edesk_percentual.py') {
    return [
      'Solicitação/trabalho: ${data['solicitacao']}/${data['idTrabalho']}',
      if (data['trabalhoNome'] != null) 'Trabalho: ${data['trabalhoNome']}',
      '% Realizado: ${data['percentualRealizado']}%',
      'Atualizar somente a porcentagem. Nenhum comentário será publicado.',
    ];
  }
  if (script == 'edesk_fases.py') {
    return [
      'Projeto: ${data['id'] ?? data['solicitacao'] ?? ''} · ${data['cliente'] ?? ''}',
      for (final phase in data['fases'] as List? ?? [])
        '${phase['nome']} · ${phase['dataInicial']} → ${phase['dataFinal']}'
    ];
  }
  return [
    'Solicitação/trabalho: ${data['solicitacao']}/${data['idTrabalho']}',
    'Tipo: ${data['tipo'] ?? ''}',
    if (data['percentualRealizado'] != null)
      '% Realizado ap\u00f3s salvar o coment\u00e1rio: ${data['percentualRealizado']}%',
  ];
}

Future<EdeskReviewDecision> reviewEdeskSend(
    Map<String, dynamic> data, String script) async {
  final context = appNavigatorKey.currentContext;
  if (context == null) return const EdeskReviewDecision(false);
  return await showDialog<EdeskReviewDecision>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _EdeskReviewDialog(data: data, script: script)) ??
      const EdeskReviewDecision(false);
}

class _EdeskReviewDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final String script;
  const _EdeskReviewDialog({required this.data, required this.script});
  @override
  State<_EdeskReviewDialog> createState() => _EdeskReviewDialogState();
}

String edeskPreparationError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is TimeoutException || error is http.ClientException) {
    return 'A integração E-Desk não respondeu. Execute Iniciar integração E-Desk.cmd neste computador e tente novamente. Se ela já estiver ativa, confira o acesso do navegador à rede local.';
  }
  return 'Não foi possível preparar o envio. Confira o estado da integração E-Desk e tente novamente. Nenhuma fase foi enviada nesta tentativa.';
}

class _EdeskReviewDialogState extends State<_EdeskReviewDialog> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final health =
          await EdeskIntegrationApi.call('/healthz', authenticated: false);
      if (health['mode'] == 'central')
        await EdeskIntegrationApi.call('/api/edesk/session');
      if (health['service'] != 'gerenciador-horas-edesk')
        throw StateError('Integração não reconhecida.');
      if (health['mode'] == 'files-only') {
        throw StateError('A abertura de arquivos está ativa, mas o envio E-Desk não. Execute Iniciar integração E-Desk.cmd e tente novamente.');
      }
      if (widget.script == 'edesk_percentual.py' && health['standalonePercentage'] != true) {
        throw StateError('Atualize a integração local para enviar somente a porcentagem.');
      }
      if (health['busy'] == true)
        throw StateError('Há outro envio em andamento. Aguarde sua conclusão.');
      if (widget.script == 'edesk_horas.py') {
        final result = await EdeskIntegrationApi.call('/api/edesk/review',
            body: {'request': widget.data});
        items = (result['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (failure) {
      error = edeskPreparationError(failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get hasUncertain =>
      items.any((e) => e['state'] == 'uncertain' || e['state'] == 'pending');
  bool get allConfirmed =>
      items.isNotEmpty && items.every((e) => e['state'] == 'confirmed');
  Future<void> confirmManually({String? key}) async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Confirmar horas já registradas'),
              content: Text(key == null
                  ? 'Você conferiu no E-Desk e verificou que todas as horas marcadas '
                      'como “Conferir no E-Desk” já estão registradas? Elas serão marcadas como confirmadas e não serão reenviadas.'
                  : 'Você conferiu no E-Desk e verificou que esta hora já está registrada? Ela será marcada como confirmada e não será reenviada.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Voltar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sim, já estão registradas'))
              ],
            ));
    if (approved != true || !mounted) return;
    setState(() => loading = true);
    try {
      await EdeskIntegrationApi.call('/api/edesk/history', body: {
        'items': {
          for (final item in items)
            if ((key != null && item['key'] == key) ||
                (key == null &&
                    (item['state'] == 'uncertain' ||
                        item['state'] == 'pending')))
              item['key']: 'confirmed',
        }
      });
      await load();
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Não foi possível salvar a conferência. Tente novamente.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = edeskReviewLines(widget.data, widget.script);
    return AlertDialog(
      title: const Text('Conferir envio ao E-Desk'),
      content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .55,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(color: Colors.orangeAccent)),
                if (widget.script == 'edesk_horas.py')
                  const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                          'Os comentários existentes serão preservados. Novos comentários serão acrescentados abaixo.')),
                for (var i = 0; i < lines.length; i++)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(lines[i]),
                                if (i < items.length)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                          switch (items[i]['state']) {
                                            'confirmed' =>
                                              'Já confirmado — não será reenviado',
                                            'pending' ||
                                            'uncertain' =>
                                          'Não confirmado na tentativa anterior',
                                            _ => 'Novo lançamento',
                                          },
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                if (i < items.length &&
                                    items[i]['state'] != 'confirmed')
                                  TextButton(
                                      onPressed: loading
                                          ? null
                                          : () => confirmManually(
                                              key: items[i]['key'] as String),
                                      child: const Text(
                                          'Esta hora já está registrada')),
                              ]))),
                if (widget.script == 'edesk_comentario.py')
                  Card(child: Padding(padding: const EdgeInsets.all(12),
                      child: widget.data['_editorDeltaPreview'] is List
                        ? CommentDocumentPreview(delta: widget.data['_editorDeltaPreview'] as List<dynamic>)
                        : EdeskCommentPreview(
                          text: widget.data['texto']?.toString() ?? '',
                          legacyImage: widget.data['imagemBase64']?.toString()))),
                if (hasUncertain) ...[
                  TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri.parse('https://promob.e-desk.com.br/'),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir E-Desk para conferir')),
                  TextButton(
                      onPressed: loading ? null : () => confirmManually(),
                      child:
                          const Text('As horas incertas já estão registradas')),
                  const Text('A nova tentativa libera os itens sem confirmação anterior. Horas já confirmadas continuam protegidas contra reenvio.'),
                ],
                if (allConfirmed)
                  const Text(
                      'Todas as horas já estão confirmadas. Não há nada novo para enviar.'),
              ]))),
      actions: [
        TextButton(
            onPressed: () =>
                Navigator.pop(context, const EdeskReviewDecision(false)),
            child: const Text('Cancelar')),
        if (error != null)
          TextButton(
              onPressed: loading ? null : load,
              child: const Text('Verificar novamente')),
        FilledButton(
            onPressed: loading ||
                    error != null ||
                    allConfirmed
                ? null
                : () => Navigator.pop(
                    context, EdeskReviewDecision(true,
                        retryUncertain: widget.script == 'edesk_horas.py')),
            child: const Text('Confirmar e enviar'))
      ],
    );
  }
}

class EdeskProgressDialog extends StatelessWidget {
  const EdeskProgressDialog({super.key});
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Envio ao E-Desk'),
        content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ValueListenableBuilder<({int completed, int total})>(
                  valueListenable: edeskProgressCounts,
                  builder: (context, counts, child) => Column(children: [
                    LinearProgressIndicator(value: counts.total > 0 && counts.completed > 0
                        ? counts.completed / counts.total : null),
                    const SizedBox(height: 8),
                    Text(counts.total > 0
                        ? '${counts.completed} de ${counts.total} itens confirmados — ${(100 * counts.completed / counts.total).floor()}%'
                        : 'Preparando o envio…'),
                  ])),
              const SizedBox(height: 20),
              ValueListenableBuilder<String>(
                  valueListenable: edeskProgress,
                  builder: (context, value, child) => Text(value)),
              const SizedBox(height: 16),
              const Text('Mantenha o app aberto e aguarde o resultado.'),
            ])),
      ));
}

class EdeskConnectionButton extends StatefulWidget {
  const EdeskConnectionButton({super.key});
  @override
  State<EdeskConnectionButton> createState() => _EdeskConnectionButtonState();
}

class _EdeskConnectionButtonState extends State<EdeskConnectionButton> {
  Timer? timer;
  bool? connected;
  bool busy = false, checking = false;
  @override
  void initState() {
    super.initState();
    check();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    try {
      final result =
          await EdeskIntegrationApi.call('/healthz', authenticated: false);
      if (result['mode'] == 'central')
        await EdeskIntegrationApi.call('/api/edesk/session');
      if (mounted)
        setState(() {
          connected = result['status'] == 'ok' &&
              result['service'] == 'gerenciador-horas-edesk';
          busy = result['busy'] == true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          connected = false;
          busy = false;
        });
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: connected == null
            ? 'Verificar integração E-Desk'
            : connected == false
                ? 'E-Desk desconectado — ver como iniciar'
                : busy
                    ? 'E-Desk conectado — envio em andamento'
                    : 'E-Desk conectado e pronto',
        onPressed: () async {
          await showIntegrationStatus(context);
          await check();
        },
        icon: Icon(connected == false ? Icons.link_off : Icons.link,
            color: connected == null
                ? Colors.grey
                : connected == false
                    ? Colors.orangeAccent
                    : busy
                        ? Colors.blueAccent
                        : Colors.greenAccent),
      );
}
