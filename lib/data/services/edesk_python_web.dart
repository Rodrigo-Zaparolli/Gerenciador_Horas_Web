import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'edesk_integration.dart';
import 'edesk_endpoint.dart';
import 'edesk_extension.dart';
import 'edesk_operation_history.dart';
import 'web_release_monitor.dart';
import 'edesk_retry_policy.dart';
import '../../features/edesk/edesk_result_dialog.dart';
import '../../features/edesk/edesk_completion.dart';

Future<EdeskPythonResult> executarPythonEdesk({
  required String requestJson,
  required bool enviar,
  String script = 'edesk_comentario.py',
  bool speakResult = false,
}) async =>
    EdeskActivity.track(() => _executar(requestJson: requestJson, enviar: enviar, script: script, speakResult: speakResult));

Future<EdeskPythonResult> executarPythonEdeskBackground({
  required String requestJson,
  required bool enviar,
  String script = 'edesk_fases.py',
}) async =>
    EdeskActivity.track(() => _executar(requestJson: requestJson, enviar: enviar, script: script));

EdeskPythonResult _failure(String message, int statusCode) => EdeskPythonResult(
      confirmed: false,
      statusCode: statusCode,
      message: message,
      responseBody: '',
    );

Future<EdeskPythonResult> _executar({
  required String requestJson,
  required bool enviar,
  required String script,
  bool speakResult = false,
}) async {
  EdeskReviewDecision decision = EdeskReviewDecision(true,
      retryUncertain: retryUnconfirmedHours(script: script, sending: enviar));
  if (enviar) {
    try {
      final data = jsonDecode(requestJson);
      if (data is! Map<String, dynamic>) {
        return _failure('Dados inválidos.', 400);
      }
      if (script != 'edesk_horas.py') {
        decision = await reviewEdeskSend(data, script);
      }
    } on FormatException {
      return _failure('Dados inválidos.', 400);
    }
    if (!decision.send) {
      return _failure(
          'Envio cancelado. Nenhum registro foi enviado nesta tentativa.', 499);
    }
  }
  // Editor snapshot is UI-only; never duplicate its images in the API payload.
  final deliveryData = jsonDecode(requestJson) as Map<String, dynamic>;
  deliveryData.remove('_editorDeltaPreview');
  requestJson = jsonEncode(deliveryData);
  final navigator = appNavigatorKey.currentState;
  String? hoursApiUrl;
  final operationId = DateTime.now().microsecondsSinceEpoch.toString();
  final historyUid = FirebaseAuth.instance.currentUser?.uid;
  String? historyId;
  try {
    historyId = EdeskOperationHistory.begin(historyUid,
        '/api/edesk/${script == 'edesk_horas.py' ? 'horas' : script == 'edesk_fases.py' ? 'fases' : script == 'edesk_percentual.py' ? 'percentual' : 'comentarios'}',
        {'request': jsonDecode(requestJson), 'enviar': enviar, 'operationId': operationId});
  } catch (_) { /* History cannot interfere with a send. */ }
  DialogRoute<void>? route;
  Timer? timer;
  bool polling = false;
  if (navigator != null && navigator.mounted) {
    edeskProgress.value = 'Abrindo E-Desk…';
    edeskProgressCounts.value = (completed: 0, total: 0);
    route = DialogRoute<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => const EdeskProgressDialog());
    unawaited(navigator.push(route));
    timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (polling) return;
      polling = true;
      try {
        final status = await EdeskIntegrationApi.call('/api/edesk/status',
            baseUrl: hoursApiUrl);
        if (status['operationId'] == operationId && timer?.isActive == true) {
          edeskProgress.value = progressLabel(status['stage'] as String?);
          final total = status['total'];
          final completed = status['completed'];
          if (total is int && total > 0 && completed is int && completed >= 0) {
            edeskProgressCounts.value = (completed: completed.clamp(0, total), total: total);
          }
        }
      } catch (_) {
        if (timer?.isActive == true) {
          edeskProgress.value =
              'Aguardando resposta. Não reenvie enquanto esta tentativa estiver em andamento.';
        }
      } finally {
        polling = false;
      }
    });
  }
  EdeskPythonResult result;
  try {
    final requiresPercentage = script == 'edesk_percentual.py' || (script == 'edesk_comentario.py' &&
        (jsonDecode(requestJson) as Map)['percentualRealizado'] != null);
    final configuredUrl = hoursApiUrl ?? await EdeskIntegrationApi.currentUrl();
    final host = Uri.parse(configuredUrl).host;
    final localIntegration = host == '127.0.0.1' || host == 'localhost';
    var useExtension = !requiresPercentage && !localIntegration && await edeskExtensionAvailable();
    if (useExtension) {
      try {
        final response = await http
            .get(Uri.parse('$configuredUrl/healthz'))
            .timeout(const Duration(seconds: 3));
        final health = jsonDecode(response.body);
        if (response.statusCode == 200 &&
            health is Map &&
            health['service'] == 'gerenciador-horas-edesk' &&
            health['mode'] == 'local' &&
            health['status'] == 'ok') {
          hoursApiUrl = configuredUrl;
          useExtension = false;
        }
      } catch (_) {
        // Availability is checked before sending; never retry a send elsewhere.
      }
    }
    if (useExtension) {
      result = await _executeExtension(
          requestJson, enviar, script, operationId, decision.retryUncertain);
    } else {
      result = await EdeskWebClient(
              apiUrl: hoursApiUrl ?? configuredUrl)
          .execute(
        requestJson: requestJson,
        enviar: enviar,
        script: script,
        operationId: operationId,
        retryUncertain: decision.retryUncertain,
      );
    }
  } catch (_) {
    result = _failure(
        'Não foi possível acessar a integração configurada. Confira a central e a conexão antes de reenviar.',
        503);
  } finally {
    timer?.cancel();
    if (route != null && navigator?.mounted == true && route.isActive) {
      navigator!.removeRoute(route);
    }
  }
  final context = appNavigatorKey.currentContext;
  EdeskOperationHistory.update(historyUid, historyId,
      result.confirmed ? (enviar ? 'confirmed' : 'tested') : 'uncertain');
  if (enviar && context != null && context.mounted) {
    await showDialog<void>(
        context: context,
        builder: (context) => EdeskResultDialog(
          confirmed: result.confirmed, message: result.message,
          operation: EdeskOperation.fromScript(script),
          includesPercentage: script == 'edesk_comentario.py' && deliveryData['percentualRealizado'] != null,
          completeProgress: edeskProgressCounts.value.total > 0 &&
              edeskProgressCounts.value.completed == edeskProgressCounts.value.total,
          spokenHoursResult: speakResult && script == 'edesk_horas.py',
          canSpeak: () => historyUid != null && FirebaseAuth.instance.currentUser?.uid == historyUid));
  }
  return result;
}

Future<EdeskPythonResult> _executeExtension(String requestJson, bool enviar,
    String script, String operationId, bool retryUncertain) async {
  const actions = {
    'edesk_comentario.py': 'comentarios',
    'edesk_fases.py': 'fases',
    'edesk_horas.py': 'horas',
  };
  final action = actions[script];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (action == null || uid == null) {
    return _failure('Entre na sua conta e selecione uma operação válida.', 400);
  }
  final accepted =
      await edeskExtensionCall('/api/edesk/$action', uid: uid, body: {
    'request': jsonDecode(requestJson),
    'enviar': enviar,
    'operationId': operationId,
    'retryUncertain': retryUncertain,
  });
  if (accepted['accepted'] != true) {
    return _failure('A extensão não aceitou o envio.', 409);
  }
  edeskProgress.value =
      'Confirme o envio na aba da extensão e entre no E-Desk, se solicitado.';
  final deadline = DateTime.now().add(const Duration(minutes: 15));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      return _failure(
          'A conta mudou. Confira a operação na aba da extensão.', 409);
    }
    final status = await edeskExtensionCall('/api/edesk/status', uid: uid);
    if (status['operationId'] != operationId) {
      return _failure(
          'A operação mudou. Confira o E-Desk antes de reenviar.', 409);
    }
    final raw = status['result'];
    if (raw is Map) {
      return EdeskPythonResult(
        confirmed: raw['confirmed'] == true,
        statusCode: raw['statusCode'] as int? ?? 409,
        message: raw['message'] as String? ?? 'Confira o resultado no E-Desk.',
        responseBody: '',
      );
    }
  }
  return _failure(
      'O envio continua na aba da extensão. Confira o resultado antes de reenviar.',
      504);
}

class EdeskWebClient {
  EdeskWebClient({
    required this.apiUrl,
    this.client,
    Future<String?> Function()? tokenProvider,
    this.timeout = const Duration(minutes: 15),
  }) : tokenProvider = tokenProvider ?? _firebaseToken;

  final String apiUrl;
  final http.Client? client;
  final Future<String?> Function() tokenProvider;
  final Duration timeout;

  static Future<String?> _firebaseToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Future<EdeskPythonResult> execute({
    required String requestJson,
    required bool enviar,
    required String script,
    String? operationId,
    bool retryUncertain = false,
  }) async {
    const actions = {
      'edesk_conferencia.py': 'conferencia',
      'edesk_recebidos.py': 'recebidos',
      'edesk_comentario.py': 'comentarios',
      'edesk_percentual.py': 'percentual',
      'edesk_fases.py': 'fases',
      'edesk_horas.py': 'horas',
    };
    final action = actions[script];
    if ((action == 'conferencia' || action == 'recebidos') && enviar) {
      return _failure('A conferência permite somente consulta.', 400);
    }
    if (action == null) {
      return _failure('Automação E-Desk não reconhecida.', 400);
    }
    if (apiUrl.trim().isEmpty) {
      return _failure(
        'Configure EDESK_API_URL para utilizar a automação E-Desk no navegador.',
        503,
      );
    }
    late final Uri base;
    try {
      base = Uri.parse(normalizeEdeskUrl(apiUrl));
    } on FormatException {
      return _failure(
          'A URL do servidor E-Desk deve usar HTTPS ou um IPv4 da rede privada.',
          503);
    }

    dynamic data;
    try {
      data = jsonDecode(requestJson);
    } on FormatException {
      return _failure('Os dados da automação não são um JSON válido.', 400);
    }
    final requestClient = client ?? http.Client();
    try {
      if (data is! Map<String, dynamic>) {
        return _failure('Os dados da automação devem ser um objeto JSON.', 400);
      }
      if ((action == 'conferencia' || action == 'recebidos') &&
          (data['url'] == null || data['url'] is String && (data['url'] as String).trim().isEmpty)) {
        data['url'] = 'https://promob.e-desk.com.br';
      }
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        return _failure(
            'Entre novamente na sua conta para utilizar o E-Desk.', 401);
      }
      final requiresPercentage =
          action == 'percentual' || (action == 'comentarios' && data['percentualRealizado'] != null);
      final requiresHoursReceipt = action == 'horas' && enviar;
      if (requiresPercentage || requiresHoursReceipt || action == 'conferencia' || action == 'recebidos' ||
          base.host == '127.0.0.1' ||
          base.host == 'localhost') {
        final healthResponse = await requestClient
            .get(base.resolve(
              '${base.path.replaceFirst(RegExp(r'/+$'), '')}/healthz',
            ))
            .timeout(const Duration(seconds: 12));
        if (healthResponse.statusCode == 200) {
          final health = jsonDecode(utf8.decode(healthResponse.bodyBytes));
          if (action == 'recebidos' && (health is! Map || health['workInbox'] != true)) {
            return _failure('Atualize e reinicie a integração v38 para buscar os trabalhos da Minha Grid.', 503);
          }
          if (action == 'conferencia' && (health is! Map || health['workAudit'] != true)) {
            return _failure('Atualize e reinicie a integração local v37 para conferir os trabalhos. Nenhuma consulta foi iniciada.', 503);
          }
          if (action == 'comentarios' && requiresPercentage &&
              (health is! Map || health['commentPercentageReceipt'] != true)) {
            return _failure('Atualize e reinicie a integração no computador que executa o E-Desk. Esta versão não confirma o comentário e a porcentagem separadamente. Nenhum comentário foi enviado.', 503);
          }
          if (action == 'percentual' && (health is! Map || health['standalonePercentage'] != true)) {
            return _failure('Atualize a integração local para enviar somente a porcentagem. Nenhum comentário foi enviado.', 503);
          }
          if (requiresPercentage &&
              (health is! Map || health['commentPercentage'] != true)) {
            return _failure(
                'Atualize a integra\u00e7\u00e3o completa em https://gerenciador-horas.web.app/integracao-completa.html para enviar o percentual. Nenhum coment\u00e1rio foi enviado nesta tentativa.',
                503);
          }
          if (health is Map && health['mode'] == 'files-only') {
            return _failure(
              'A abertura local de arquivos está ativa, mas não envia horas ao E-Desk. Instale e ative a extensão E-Desk neste navegador e atualize o app com Ctrl + F5.',
              503,
            );
          }
          if (requiresHoursReceipt && (health is! Map || health['hoursReconciliation'] != true)) {
            return _failure('Atualize e reinicie a integração v36 no computador que executa o E-Desk para conferir e recuperar horas pendentes sem repetir cadastros. Nenhuma hora foi enviada nesta tentativa.', 503);
          }
        } else if (action == 'recebidos') {
          return _failure('A integração não confirmou o suporte a trabalhos recebidos. Atualize para v38.', 503);
        } else if (action == 'conferencia') {
          return _failure('A integração não confirmou o suporte à conferência. Atualize e reinicie a integração v37.', 503);
        } else if (requiresHoursReceipt) {
          return _failure('A integração não confirmou o suporte à conferência de horas. Atualize e reinicie a integração v36. Nenhuma hora foi enviada.', 503);
        } else if (requiresPercentage) {
          return _failure(
              'A integra\u00e7\u00e3o n\u00e3o confirmou o suporte ao percentual. Nenhum coment\u00e1rio foi enviado.',
              503);
        }
      }
      final endpoint = base.resolve(
        '${base.path.replaceFirst(RegExp(r'/+$'), '')}/api/edesk/$action',
      );
      final response = await requestClient
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'request': data,
              'enviar': enviar,
              if (operationId != null) 'operationId': operationId,
              if (retryUncertain) 'retryUncertain': true
            }),
          )
          .timeout(timeout);
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (result is! Map<String, dynamic>) {
        return _failure(
            'O servidor E-Desk retornou uma resposta inválida.', 502);
      }
      final total = result['total'];
      final completed = result['completed'];
      if (total is int && total > 0 && completed is int && completed >= 0) {
        edeskProgressCounts.value = (completed: completed.clamp(0, total), total: total);
      }
      return EdeskPythonResult(
        confirmed: response.statusCode == 200 && result['confirmed'] == true,
        statusCode: response.statusCode,
        message: result['message'] is String
            ? result['message'] as String
            : 'O servidor E-Desk não confirmou a operação.',
        responseBody: result['responseBody'] is String
            ? result['responseBody'] as String
            : '',
      );
    } on TimeoutException {
      return _failure(
        'O servidor demorou para responder. Verifique o E-Desk antes de reenviar.',
        504,
      );
    } on FormatException {
      return _failure(
          'Não foi possível interpretar os dados da automação.', 502);
    } catch (_) {
      return _failure(
        base.host == '127.0.0.1' || base.host == 'localhost'
            ? 'Não foi possível conectar à integração E-Desk deste computador. '
                'Abra o atalho Iniciar integração E-Desk e permita o acesso '
                'local no navegador. Depois tente novamente.'
            : 'Não foi possível acessar o servidor E-Desk. Verifique sua conexão '
                'e a configuração do servidor.',
        503,
      );
    } finally {
      if (client == null) requestClient.close();
    }
  }
}

class EdeskPythonResult {
  final bool confirmed;
  final int statusCode;
  final String message;
  final String responseBody;

  const EdeskPythonResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}
