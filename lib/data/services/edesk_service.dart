import 'dart:async';
import 'dart:convert';
import 'package:gerenciador_horas/data/services/edesk_python.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';

/// ================================================================
/// DADOS DO TRABALHO E-DESK
/// ================================================================

class EdeskWorkData {
  final Uri pageUri;
  final String solicitacao;
  final String idTrabalho;
  final String data;
  final String horaInicio;
  final String horaFim;
  final String tipoRegistro;
  final String tarefa;
  final String descricao;
  final String trabalhoRealizado;

  final String? gtt;
  final String? equipamento;
  final String? atendimento;
  final String? motivo;

  const EdeskWorkData({
    required this.pageUri,
    required this.solicitacao,
    required this.idTrabalho,
    required this.data,
    required this.horaInicio,
    required this.horaFim,
    required this.tipoRegistro,
    required this.tarefa,
    required this.descricao,
    this.trabalhoRealizado = '',
    this.gtt,
    this.equipamento,
    this.atendimento,
    this.motivo,
  });

  String get referencia {
    final solicitacaoValue = solicitacao.trim();
    final trabalhoValue = idTrabalho.trim();

    if (solicitacaoValue.isEmpty && trabalhoValue.isEmpty) {
      return '';
    }

    if (trabalhoValue.isEmpty) {
      return solicitacaoValue;
    }

    if (solicitacaoValue.isEmpty) {
      return trabalhoValue;
    }

    return '$solicitacaoValue/$trabalhoValue';
  }

  EdeskWorkData copyWith({
    Uri? pageUri,
    String? solicitacao,
    String? idTrabalho,
    String? data,
    String? horaInicio,
    String? horaFim,
    String? tipoRegistro,
    String? tarefa,
    String? descricao,
    String? trabalhoRealizado,
    String? gtt,
    String? equipamento,
    String? atendimento,
    String? motivo,
  }) {
    return EdeskWorkData(
      pageUri: pageUri ?? this.pageUri,
      solicitacao: solicitacao ?? this.solicitacao,
      idTrabalho: idTrabalho ?? this.idTrabalho,
      data: data ?? this.data,
      horaInicio: horaInicio ?? this.horaInicio,
      horaFim: horaFim ?? this.horaFim,
      tipoRegistro: tipoRegistro ?? this.tipoRegistro,
      tarefa: tarefa ?? this.tarefa,
      descricao: descricao ?? this.descricao,
      trabalhoRealizado: trabalhoRealizado ?? this.trabalhoRealizado,
      gtt: gtt ?? this.gtt,
      equipamento: equipamento ?? this.equipamento,
      atendimento: atendimento ?? this.atendimento,
      motivo: motivo ?? this.motivo,
    );
  }
}

/// ================================================================
/// RESULTADO
/// ================================================================

class EdeskSendResult {
  final bool confirmed;
  final int statusCode;
  final String message;
  final String responseBody;

  const EdeskSendResult({
    required this.confirmed,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}

/// ================================================================
/// EXCEÇÕES
/// ================================================================

class EdeskException implements Exception {
  final String message;

  const EdeskException(this.message);

  @override
  String toString() => message;
}

class EdeskAuthenticationException extends EdeskException {
  const EdeskAuthenticationException(
    super.message,
  );
}

/// ================================================================
/// SERVIÇO E-DESK
/// ================================================================

class EdeskService {
  EdeskService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  final Map<String, String> _cookies = {};

  /// ==============================================================
  /// SESSÃO
  /// ==============================================================

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  bool get hasSession => _cookies.isNotEmpty;

  void setSessionCookies(
    Map<String, String> cookies,
  ) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

  void clearSession() {
    _cookies.clear();
  }

  /// ==============================================================
  /// URL OFICIAL DA LISTA
  /// ==============================================================

  static final Uri listaSolicitacaoPadrao = Uri.parse(
    'https://promob.e-desk.com.br/Portal/'
    'ListaSolicitacao.aspx'
    '?GUID=ff841454-6398-4e36-84e5-0ce750d161a5',
  );

  /// ==============================================================
  /// ABRIR URL
  /// ==============================================================

  Future<bool> abrirEdesk({
    Uri? uri,
  }) async {
    final target = uri ?? listaSolicitacaoPadrao;

    try {
      return await launchUrl(
        target,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      throw EdeskException(
        'Não foi possível abrir o E-Desk no navegador: $e',
      );
    }
  }

  /// ==============================================================
  /// ABRIR URL INFORMADA
  /// ==============================================================

  Future<bool> abrirPorUrl({
    required String url,
  }) async {
    final uri = Uri.tryParse(
      url.trim(),
    );

    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }

    return abrirEdesk(
      uri: uri,
    );
  }

  /// ==============================================================
  /// ABRIR LISTA
  /// ==============================================================

  Future<bool> abrirListaSolicitacoes() {
    return abrirEdesk(
      uri: listaSolicitacaoPadrao,
    );
  }

  /// ==============================================================
  /// RESOLVER URL REAL DO TRABALHO
  /// ==============================================================

  Future<Uri> resolveWorkPageUri({
    required String solicitacao,
    required String idTrabalho,
    Uri? listaUri,
  }) async {
    final solicitacaoNumero = solicitacao.trim();

    final trabalhoNumero = idTrabalho.trim();

    if (solicitacaoNumero.isEmpty) {
      throw const EdeskException(
        'O número da solicitação não foi informado.',
      );
    }

    if (trabalhoNumero.isEmpty) {
      throw const EdeskException(
        'O número do trabalho não foi informado.',
      );
    }

    final origem = listaUri ?? listaSolicitacaoPadrao;

    debugPrint(
      '[E-Desk] Procurando trabalho '
      '$solicitacaoNumero/$trabalhoNumero',
    );

    debugPrint(
      '[E-Desk] Lista: $origem',
    );

    final listaResponse = await _getPage(
      origem,
      operation: 'localizar a solicitação $solicitacaoNumero',
    );

    final listaHtml = _decodeResponse(
      listaResponse,
    );

    _ensureAuthenticated(
      listaResponse,
      listaHtml,
    );

    debugPrint(
      '[E-Desk] Lista carregada. '
      'HTML: ${listaHtml.length} caracteres',
    );

    final direto = _findWorkLinkInHtml(
      html: listaHtml,
      solicitacao: solicitacaoNumero,
      trabalho: trabalhoNumero,
      baseUri: origem,
    );

    if (direto != null) {
      final resultado = _toRetroactiveUri(
        direto,
      );

      debugPrint(
        '[E-Desk] Trabalho encontrado diretamente:',
      );

      debugPrint(
        '[E-Desk] $resultado',
      );

      return resultado;
    }

    final solicitacaoUri = _findSolicitationLink(
      html: listaHtml,
      solicitacao: solicitacaoNumero,
      baseUri: origem,
    );

    if (solicitacaoUri == null) {
      throw EdeskException(
        'A solicitação $solicitacaoNumero '
        'não foi encontrada na lista do E-Desk.',
      );
    }

    debugPrint(
      '[E-Desk] Solicitação encontrada:',
    );

    debugPrint(
      '[E-Desk] $solicitacaoUri',
    );

    final solicitacaoResponse = await _getPage(
      solicitacaoUri,
      operation: 'abrir a solicitação $solicitacaoNumero',
    );

    final solicitacaoHtml = _decodeResponse(
      solicitacaoResponse,
    );

    _ensureAuthenticated(
      solicitacaoResponse,
      solicitacaoHtml,
    );

    debugPrint(
      '[E-Desk] Página da solicitação carregada. '
      'HTML: ${solicitacaoHtml.length} caracteres',
    );

    final trabalhoUri = _findWorkLinkInHtml(
      html: solicitacaoHtml,
      solicitacao: solicitacaoNumero,
      trabalho: trabalhoNumero,
      baseUri: solicitacaoUri,
    );

    if (trabalhoUri == null) {
      throw EdeskException(
        'A solicitação $solicitacaoNumero foi encontrada, '
        'mas o trabalho $trabalhoNumero não foi localizado.',
      );
    }

    final resultado = _toRetroactiveUri(
      trabalhoUri,
    );

    debugPrint(
      '[E-Desk] ========================================',
    );

    debugPrint(
      '[E-Desk] TRABALHO ENCONTRADO',
    );

    debugPrint(
      '[E-Desk] Solicitação: $solicitacaoNumero',
    );

    debugPrint(
      '[E-Desk] Trabalho: $trabalhoNumero',
    );

    debugPrint(
      '[E-Desk] URL REAL:',
    );

    debugPrint(
      '[E-Desk] $resultado',
    );

    debugPrint(
      '[E-Desk] ========================================',
    );

    return resultado;
  }

  /// ==============================================================
  /// ABRIR POR REFERÊNCIA
  /// ==============================================================

  Future<bool> abrirPorReferencia({
    required String solicitacao,
    required String idTrabalho,
  }) async {
    final solicitacaoNumero = solicitacao.trim();

    final trabalhoNumero = idTrabalho.trim();

    if (solicitacaoNumero.isEmpty || trabalhoNumero.isEmpty) {
      throw const EdeskException(
        'Não foi possível identificar a solicitação '
        'e o trabalho.',
      );
    }

    final uri = await resolveWorkPageUri(
      solicitacao: solicitacaoNumero,
      idTrabalho: trabalhoNumero,
    );

    return abrirEdesk(
      uri: uri,
    );
  }

  /// ==============================================================
  /// RESOLVER E ABRIR
  /// ==============================================================

  Future<bool> resolverEAbrir({
    required String solicitacao,
    required String idTrabalho,
    Uri? listaUri,
  }) async {
    final uri = await resolveWorkPageUri(
      solicitacao: solicitacao,
      idTrabalho: idTrabalho,
      listaUri: listaUri,
    );

    return abrirEdesk(
      uri: uri,
    );
  }

  /// ==============================================================
  /// ENVIAR POR REFERÊNCIA
  /// ==============================================================

  Future<EdeskSendResult> sendWorkByReference({
    required EdeskWorkData work,
    Uri? listaUri,
  }) async {
    final pageUri = await resolveWorkPageUri(
      solicitacao: work.solicitacao,
      idTrabalho: work.idTrabalho,
      listaUri: listaUri,
    );

    return sendWork(
      work.copyWith(
        pageUri: pageUri,
      ),
    );
  }

  /// ==============================================================
  /// HTTP GET
  /// ==============================================================

  Future<http.Response> _getPage(
    Uri uri, {
    required String operation,
  }) async {
    late final http.Response response;

    try {
      response = await _client
          .get(
            uri,
            headers: _headers(),
          )
          .timeout(
            const Duration(
              seconds: 30,
            ),
          );
    } on TimeoutException {
      throw EdeskException(
        'Tempo esgotado ao $operation no E-Desk.',
      );
    } on Exception catch (e) {
      throw EdeskException(
        _connectionErrorMessage(
          operation: operation,
          uri: uri,
          error: e,
        ),
      );
    }

    _storeCookies(
      response,
    );

    _debugResponse(
      operation: 'GET $operation',
      uri: uri,
      response: response,
    );

    if (response.statusCode >= 300 && response.statusCode < 400) {
      if (_isRedirectToLogin(
        response,
      )) {
        throw const EdeskAuthenticationException(
          'A sessão do E-Desk não está autenticada '
          'ou expirou.',
        );
      }
    }

    if (response.statusCode != 200) {
      throw EdeskException(
        'Não foi possível $operation. '
        'HTTP ${response.statusCode}.',
      );
    }

    return response;
  }

  /// ==============================================================
  /// LOCALIZAR SOLICITAÇÃO
  /// ==============================================================

  Uri? _findSolicitationLink({
    required String html,
    required String solicitacao,
    required Uri baseUri,
  }) {
    final anchors = _extractAnchors(
      html,
    );

    for (final anchor in anchors) {
      final href = anchor.href;

      final text = _normalizeHtmlText(
        anchor.text,
      );

      if (href == null || href.isEmpty) {
        continue;
      }

      final lowerHref = href.toLowerCase();

      if (!lowerHref.contains(
        'solicitacao.aspx',
      )) {
        continue;
      }

      if (_containsVisibleNumber(
            text,
            solicitacao,
          ) ||
          _containsVisibleNumber(
            href,
            solicitacao,
          )) {
        return _resolveHref(
          baseUri,
          href,
        );
      }
    }

    final rows = RegExp(
      r'<tr\b[^>]*>(.*?)</tr>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in rows.allMatches(html)) {
      final row = match.group(1) ?? '';

      final rowText = _normalizeHtmlText(
        row,
      );

      if (!_containsVisibleNumber(
        rowText,
        solicitacao,
      )) {
        continue;
      }

      for (final anchor in _extractAnchors(row)) {
        final href = anchor.href;

        if (href != null &&
            href.isNotEmpty &&
            href.toLowerCase().contains(
                  'solicitacao.aspx',
                )) {
          return _resolveHref(
            baseUri,
            href,
          );
        }
      }
    }

    return null;
  }

  /// ==============================================================
  /// LOCALIZAR TRABALHO
  /// ==============================================================

  Uri? _findWorkLinkInHtml({
    required String html,
    required String solicitacao,
    required String trabalho,
    required Uri baseUri,
  }) {
    final anchors = _extractAnchors(
      html,
    );

    for (final anchor in anchors) {
      final href = anchor.href;

      final text = _normalizeHtmlText(
        anchor.text,
      );

      if (href == null || href.isEmpty) {
        continue;
      }

      if (!_isWorkHref(
        href,
      )) {
        continue;
      }

      if (_containsVisibleNumber(
        text,
        trabalho,
      )) {
        return _resolveHref(
          baseUri,
          href,
        );
      }
    }

    final rows = RegExp(
      r'<tr\b[^>]*>(.*?)</tr>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in rows.allMatches(html)) {
      final row = match.group(1) ?? '';

      final rowText = _normalizeHtmlText(
        row,
      );

      if (!_containsVisibleNumber(
        rowText,
        trabalho,
      )) {
        continue;
      }

      for (final anchor in _extractAnchors(row)) {
        final href = anchor.href;

        if (href != null &&
            _isWorkHref(
              href,
            )) {
          return _resolveHref(
            baseUri,
            href,
          );
        }
      }
    }

    for (final anchor in anchors) {
      final href = anchor.href;

      if (href == null ||
          !_isWorkHref(
            href,
          )) {
        continue;
      }

      final marker = html.indexOf(
        href,
      );

      if (marker < 0) {
        continue;
      }

      final start = marker > 1200 ? marker - 1200 : 0;

      final end = marker + href.length + 1200 > html.length
          ? html.length
          : marker + href.length + 1200;

      final context = _normalizeHtmlText(
        html.substring(
          start,
          end,
        ),
      );

      if (_containsVisibleNumber(
        context,
        trabalho,
      )) {
        return _resolveHref(
          baseUri,
          href,
        );
      }
    }

    return null;
  }

  /// ==============================================================
  /// IDENTIFICAR LINK DE TRABALHO
  /// ==============================================================

  bool _isWorkHref(
    String href,
  ) {
    final normalized = href.toLowerCase();

    return normalized.contains(
          'trabalho.aspx',
        ) ||
        normalized.contains(
          'trabalhoretroativo.aspx',
        );
  }

  /// ==============================================================
  /// VERIFICAR NÚMERO EXATO
  /// ==============================================================

  bool _containsVisibleNumber(
    String text,
    String number,
  ) {
    final normalizedText = _normalizeHtmlText(
      text,
    );

    final value = number.trim();

    if (value.isEmpty) {
      return false;
    }

    final pattern = RegExp(
      r'(?<!\d)' + RegExp.escape(value) + r'(?!\d)',
    );

    return pattern.hasMatch(
      normalizedText,
    );
  }

  /// ==============================================================
  /// EXTRAIR LINKS
  /// ==============================================================

  List<_HtmlAnchor> _extractAnchors(
    String html,
  ) {
    final anchors = <_HtmlAnchor>[];

    final pattern = RegExp(
      r'''<a\b[^>]*href\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in pattern.allMatches(html)) {
      final href = match.group(1) ?? match.group(2);

      final text = match.group(3) ?? '';

      anchors.add(
        _HtmlAnchor(
          href,
          text,
        ),
      );
    }

    return anchors;
  }

  /// ==============================================================
  /// RESOLVER HREF
  /// ==============================================================

  Uri _resolveHref(
    Uri baseUri,
    String href,
  ) {
    final cleaned = href
        .replaceAll(
          '&amp;',
          '&',
        )
        .replaceAll(
          '&#39;',
          "'",
        )
        .replaceAll(
          '&quot;',
          '"',
        )
        .trim();

    final parsed = Uri.tryParse(
      cleaned,
    );

    if (parsed == null) {
      throw EdeskException(
        'O E-Desk retornou um link inválido.',
      );
    }

    return parsed.hasScheme
        ? parsed
        : baseUri.resolve(
            cleaned,
          );
  }

  /// ==============================================================
  /// TRABALHO -> TRABALHORETROATIVO
  /// ==============================================================

  Uri _toRetroactiveUri(
    Uri uri,
  ) {
    final path = uri.path;

    if (path.toLowerCase().endsWith(
          '/trabalhoretroativo.aspx',
        )) {
      return uri;
    }

    if (path.toLowerCase().endsWith(
          '/trabalho.aspx',
        )) {
      return uri.replace(
        path: '${path.substring(
          0,
          path.length - 'Trabalho.aspx'.length,
        )}'
            'TrabalhoRetroativo.aspx',
      );
    }

    return uri;
  }

  /// ==============================================================
  /// NORMALIZAR HTML
  /// ==============================================================

  String _normalizeHtmlText(
    String value,
  ) {
    return value
        .replaceAll(
          RegExp(
            r'<[^>]+>',
          ),
          ' ',
        )
        .replaceAll(
          '&nbsp;',
          ' ',
        )
        .replaceAll(
          '&amp;',
          '&',
        )
        .replaceAll(
          '&quot;',
          '"',
        )
        .replaceAll(
          '&#39;',
          "'",
        )
        .replaceAll(
          RegExp(
            r'\s+',
          ),
          ' ',
        )
        .trim();
  }

  /// ==============================================================
  /// AUTENTICAÇÃO
  /// ==============================================================

  void _ensureAuthenticated(
    http.Response response,
    String html,
  ) {
    if (_isRedirectToLogin(
          response,
        ) ||
        _looksLikeLoginPage(
          html,
        )) {
      throw const EdeskAuthenticationException(
        'O E-Desk retornou a tela de login. '
        'A sessão HTTP do aplicativo não está autenticada.',
      );
    }
  }

  bool _isRedirectToLogin(
    http.Response response,
  ) {
    if (response.statusCode < 300 || response.statusCode >= 400) {
      return false;
    }

    final location = response.headers['location'];

    if (location == null) {
      return false;
    }

    return _looksLikeLoginUrl(
      location,
    );
  }

  bool _looksLikeLoginPage(
    String body,
  ) {
    final normalized = body.toLowerCase();

    final hasLoginMarker = normalized.contains(
          'promob identity',
        ) ||
        normalized.contains(
          'login.aspx',
        ) ||
        normalized.contains(
          'signin',
        ) ||
        normalized.contains(
          'entrar',
        );

    final hasPasswordField = normalized.contains(
          'type="password"',
        ) ||
        normalized.contains(
          "type='password'",
        );

    final hasUserField = normalized.contains(
          'usuário',
        ) ||
        normalized.contains(
          'usuario',
        ) ||
        normalized.contains(
          'username',
        );

    if (hasLoginMarker && hasPasswordField) {
      return true;
    }

    if (hasUserField && hasPasswordField) {
      return true;
    }

    return false;
  }

  bool _looksLikeLoginUrl(
    String url,
  ) {
    final normalized = url.toLowerCase();

    return normalized.contains(
          'login',
        ) ||
        normalized.contains(
          'signin',
        ) ||
        normalized.contains(
          'identity',
        );
  }

  /// ==============================================================
  /// COOKIES
  /// ==============================================================

  void _storeCookies(
    http.Response response,
  ) {
    final values = response.headers['set-cookie'];

    if (values == null || values.isEmpty) {
      return;
    }

    final cookies = values.split(
      RegExp(
        r',(?=\s*[^;,=]+\s*=)',
      ),
    );

    for (final cookie in cookies) {
      final firstPart = cookie.split(';').first.trim();

      final separator = firstPart.indexOf(
        '=',
      );

      if (separator <= 0) {
        continue;
      }

      final name = firstPart
          .substring(
            0,
            separator,
          )
          .trim();

      final value = firstPart
          .substring(
            separator + 1,
          )
          .trim();

      if (name.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Accept': 'text/html,application/xhtml+xml,'
          'application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 '
          '(KHTML, like Gecko) '
          'Chrome/140.0.0.0 Safari/537.36',
    };

    if (_cookies.isNotEmpty) {
      headers['Cookie'] = _cookieHeader();
    }

    return headers;
  }

  String _cookieHeader() {
    return _cookies.entries
        .map(
          (entry) => '${entry.key}=${entry.value}',
        )
        .join('; ');
  }

  /// ==============================================================
  /// RESPONSE
  /// ==============================================================

  String _decodeResponse(
    http.Response response,
  ) {
    return utf8.decode(
      response.bodyBytes,
      allowMalformed: true,
    );
  }

  /// ==============================================================
  /// DEBUG
  /// ==============================================================

  void _debugResponse({
    required String operation,
    required Uri uri,
    required http.Response response,
  }) {
    final contentType = response.headers['content-type'] ?? 'não informado';

    final location = response.headers['location'];

    debugPrint(
      '[E-Desk][$operation] '
      'HTTP ${response.statusCode} '
      'host=${uri.host} '
      'content-type=$contentType'
      '${location != null ? ' location=${_sanitizeLocation(location)}' : ''}',
    );
  }

  String _sanitizeLocation(
    String location,
  ) {
    final uri = Uri.tryParse(
      location,
    );

    if (uri == null) {
      return '<redirect>';
    }

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  /// ==============================================================
  /// SEND WORK
  /// ==============================================================

  Future<EdeskSendResult> sendWork(
    EdeskWorkData work,
  ) async {
    final referencia = work.referencia;

    debugPrint(
      '[E-Desk] Abrindo trabalho '
      '$referencia',
    );

    final abriu = await abrirEdesk(
      uri: work.pageUri,
    );

    return EdeskSendResult(
      confirmed: abriu,
      statusCode: abriu ? 200 : 0,
      message: abriu
          ? 'E-Desk aberto no navegador para conferir '
              '$referencia.'
          : 'Não foi possível abrir o E-Desk para '
              '$referencia.',
      responseBody: '',
    );
  }

  /// ==============================================================
  /// ERRO DE CONEXÃO
  /// ==============================================================

  String _connectionErrorMessage({
    required String operation,
    required Uri uri,
    required Exception error,
  }) {
    final detail = error.toString().trim();

    return 'Erro ao $operation no E-Desk. '
        'Tipo: ${error.runtimeType}. '
        'Detalhe: '
        '${detail.isEmpty ? 'sem detalhes adicionais' : detail}. '
        'Servidor: ${uri.host}.';
  }

  /// ==============================================================
  /// ATUALIZAR DATAS DAS FASES VIA PYTHON
  ///
  /// FLUXO:
  /// - Localiza a solicitação pelo ID
  /// - Confere o Cliente
  /// - Localiza as fases pelo nome
  /// - Atualiza Data Inicial Ajustada
  /// - Atualiza Data Final Ajustada
  /// - Salva no E-Desk
  ///
  /// CREDENCIAIS:
  /// - Lê e-mail e senha salvos no FlutterSecureStorage
  /// - Envia ao Python apenas durante a execução
  /// - Nunca imprime a senha no log
  ///
  /// O Python roda em BACKGROUND porque mantém o navegador aberto.
  /// ==============================================================

  Future<EdeskSendResult> atualizarFasesViaPython({
    required String id,
    required String cliente,
    required List<Map<String, String>> fases,
    void Function(
      bool sucesso,
      String mensagem,
    )? onConcluido,
  }) async {
    final idValue = id.trim();
    final clienteValue = cliente.trim();

    // =============================================================
    // VALIDAÇÕES
    // =============================================================

    if (idValue.isEmpty) {
      return const EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'O ID da solicitação não foi informado.',
        responseBody: '',
      );
    }

    if (clienteValue.isEmpty) {
      return const EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'O cliente não foi informado.',
        responseBody: '',
      );
    }

    if (fases.isEmpty) {
      return const EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'Nenhuma fase foi informada para atualização.',
        responseBody: '',
      );
    }

    // =============================================================
    // CREDENCIAIS E-DESK
    // =============================================================

    final credenciais = await EdeskCredentialsService().ler();

    debugPrint(
      '[E-Desk] Credenciais automáticas: '
      '${credenciais != null ? 'disponíveis' : 'não cadastradas'}',
    );

    // =============================================================
    // DEBUG
    // =============================================================

    debugPrint(
      '[E-Desk] ========================================',
    );

    debugPrint(
      '[E-Desk] Atualizando datas das fases via Python',
    );

    debugPrint(
      '[E-Desk] ID: $idValue',
    );

    debugPrint(
      '[E-Desk] Cliente: $clienteValue',
    );

    debugPrint(
      '[E-Desk] Quantidade de fases: ${fases.length}',
    );

    for (final fase in fases) {
      debugPrint(
        '[E-Desk] Fase: ${fase['nome']} | '
        'Inicial: ${fase['dataInicial']} | '
        'Final: ${fase['dataFinal']}',
      );
    }

    debugPrint(
      '[E-Desk] ========================================',
    );

    // =============================================================
    // JSON PARA O PYTHON
    // =============================================================

    final requestJson = jsonEncode({
      'id': idValue,
      'cliente': clienteValue,
      'fases': fases,
      'edeskCredenciais': credenciais == null
          ? null
          : {
              'email': credenciais['email'],
              'senha': credenciais['senha'],
            },
    });

    // IMPORTANTE:
    // NÃO imprimir requestJson porque ele contém a senha.

    debugPrint(
      '[E-Desk] Dados enviados ao Python. '
      'Credenciais: '
      '${credenciais != null ? 'sim' : 'não'}',
    );

    // =============================================================
    // EXECUTAR PYTHON EM BACKGROUND
    //
    // Esta função retorna void no seu projeto.
    // Portanto NÃO tentamos capturar um "resultado".
    // =============================================================

    try {
      final resultado = await executarPythonEdeskBackground(
        requestJson: requestJson,
        enviar: true,
        script: 'edesk_fases.py',
      );

      return EdeskSendResult(
        confirmed: resultado.confirmed,
        statusCode: resultado.statusCode,
        message: resultado.message,
        responseBody: resultado.responseBody,
      );
    } catch (e) {
      debugPrint(
        '[E-Desk] ERRO ao iniciar atualização das fases: $e',
      );

      return EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'Erro ao iniciar atualização das fases no E-Desk: $e',
        responseBody: '',
      );
    }
  }

  /// ==============================================================
  /// EXECUTAR COMENTÁRIO VIA PYTHON
  /// ==============================================================
  Future<EdeskSendResult> executarComentarioViaPython({
    required Uri pageUri,
    required String solicitacao,
    required String idTrabalho,
    required String tipoComentario,
    required String texto,
    String? imagemBase64,
    double? percentualRealizado,
    required bool enviar,
  }) async {
    final solicitacaoValue = solicitacao.trim();
    final trabalhoValue = idTrabalho.trim();

    // =============================================================
    // O ID DO TRABALHO É OBRIGATÓRIO
    // =============================================================
    if (trabalhoValue.isEmpty) {
      return const EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'O ID do trabalho E-Desk não foi informado.',
        responseBody: '',
      );
    }

    // =============================================================
    // CREDENCIAIS E-DESK
    // =============================================================

    final credenciais = await EdeskCredentialsService().ler();

    debugPrint(
      '[E-Desk] Credenciais automáticas para comentário: '
      '${credenciais != null ? 'disponíveis' : 'não cadastradas'}',
    );

    // =============================================================
    // DEBUG
    // =============================================================

    debugPrint(
      '[E-Desk] ========================================',
    );

    debugPrint(
      '[E-Desk] Executando comentário via Python',
    );

    debugPrint(
      '[E-Desk] Solicitação: '
      '${solicitacaoValue.isEmpty ? "<não informada>" : solicitacaoValue}',
    );

    debugPrint(
      '[E-Desk] ID Trabalho: $trabalhoValue',
    );

    debugPrint(
      '[E-Desk] URL: $pageUri',
    );

    debugPrint(
      '[E-Desk] Tipo: $tipoComentario',
    );

    debugPrint(
      '[E-Desk] Enviar: $enviar',
    );

    debugPrint(
      '[E-Desk] Credenciais: '
      '${credenciais != null ? 'sim' : 'não'}',
    );

    debugPrint(
      '[E-Desk] ========================================',
    );

    // =============================================================
    // REQUEST PARA O PYTHON
    // =============================================================

    final requestJson = jsonEncode({
      'url': pageUri.toString(),

      'solicitacao': solicitacaoValue,

      'idTrabalho': trabalhoValue,

      'tipo': tipoComentario,

      'texto': texto,

      'imagemBase64': imagemBase64,
      if (percentualRealizado != null)
        'percentualRealizado': percentualRealizado,

      'enviar': enviar,

      // ===========================================================
      // CREDENCIAIS
      // ===========================================================

      'edeskCredenciais': credenciais == null
          ? null
          : {
              'email': credenciais['email'],
              'senha': credenciais['senha'],
            },
    });

    // IMPORTANTE:
    // NÃO imprimir requestJson.
    // Ele contém a senha do E-Desk.

    // =============================================================
    // EXECUTA PYTHON
    // =============================================================

    try {
      final resultado = await executarPythonEdesk(
        requestJson: requestJson,
        enviar: enviar,
        script: 'edesk_comentario.py',
      );

      debugPrint(
        '[E-Desk] Python finalizado.',
      );

      debugPrint(
        '[E-Desk] Confirmado: ${resultado.confirmed}',
      );

      debugPrint(
        '[E-Desk] Status: ${resultado.statusCode}',
      );

      debugPrint(
        '[E-Desk] Mensagem: ${resultado.message}',
      );

      return EdeskSendResult(
        confirmed: resultado.confirmed,
        statusCode: resultado.statusCode,
        message: resultado.message,
        responseBody: resultado.responseBody,
      );
    } catch (e) {
      debugPrint(
        '[E-Desk] ERRO ao executar Python: $e',
      );

      return EdeskSendResult(
        confirmed: false,
        statusCode: 0,
        message: 'Erro ao executar integração E-Desk: $e',
        responseBody: '',
      );
    }
  }

  /// ==============================================================
  /// DISPOSE
  /// ==============================================================

  void dispose() {
    _client.close();
  }
}

/// ================================================================
/// LINK HTML
/// ================================================================

class _HtmlAnchor {
  final String? href;
  final String text;

  const _HtmlAnchor(
    this.href,
    this.text,
  );
}
