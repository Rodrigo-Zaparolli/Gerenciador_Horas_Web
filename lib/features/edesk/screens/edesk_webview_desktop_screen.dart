import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

class EdeskWebViewTestScreen extends StatefulWidget {
  final String? solicitacao;
  final String? idTrabalho;

  const EdeskWebViewTestScreen({
    super.key,
    this.solicitacao,
    this.idTrabalho,
  });

  @override
  State<EdeskWebViewTestScreen> createState() => _EdeskWebViewTestScreenState();
}

class _EdeskWebViewTestScreenState extends State<EdeskWebViewTestScreen> {
  static const String _urlEdesk =
      'https://promob.e-desk.com.br/Portal/ListaSolicitacao.aspx?GUID=ff841454-6398-4e36-84e5-0ce750d161a5';

  final WebviewController _controller = WebviewController();

  StreamSubscription<String>? _urlSubscription;
  StreamSubscription<HistoryChanged>? _historySubscription;
  StreamSubscription<LoadingState>? _loadingSubscription;

  Timer? _automacaoTimer;

  String _currentUrl = '';
  String? _erro;
  String _status = 'Inicializando E-Desk...';

  bool _carregando = true;
  bool _inicializado = false;

  bool _procurandoSolicitacao = false;
  bool _procurandoTrabalho = false;
  bool _trabalhoEncontrado = false;


  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  // ============================================================
  // INICIALIZAÇÃO
  // ============================================================

  Future<void> _inicializar() async {
    _automacaoTimer?.cancel();

    try {
      debugPrint('========== E-DESK WEBVIEW ==========');
      debugPrint('Solicitação: ${widget.solicitacao}');
      debugPrint('ID Trabalho: ${widget.idTrabalho}');
      debugPrint('=====================================');

      final appData = await getApplicationSupportDirectory();

      final pastaEdesk = Directory(
        '${appData.path}${Platform.pathSeparator}EdeskWebView',
      );

      if (!await pastaEdesk.exists()) {
        await pastaEdesk.create(recursive: true);
      }

      debugPrint(
        '[E-Desk] Perfil persistente: ${pastaEdesk.path}',
      );

      // O ambiente persistente já é inicializado no main.dart.
      await _controller.initialize();

      // ==========================================================
      // URL
      // ==========================================================

      _urlSubscription = _controller.url.listen((url) {
        if (!mounted) return;

        setState(() {
          _currentUrl = url;
        });

        debugPrint('[E-Desk] URL: $url');

        // ========================================================
        // TRABALHO REAL ENCONTRADO
        // ========================================================

        if (url.contains('/Portal/Trabalho.aspx') &&
            url.contains('id_trabalho=')) {
          _trabalhoEncontrado = true;

          debugPrint('');
          debugPrint('==========================================');
          debugPrint('[E-Desk] TRABALHO REAL ENCONTRADO');
          debugPrint('[E-Desk] Solicitação: ${widget.solicitacao}');
          debugPrint('[E-Desk] Trabalho: ${widget.idTrabalho}');
          debugPrint('[E-Desk] URL REAL:');
          debugPrint(url);
          debugPrint('==========================================');
          debugPrint('');

          if (mounted) {
            setState(() {
              _status = 'Trabalho ${widget.idTrabalho} encontrado.';
            });
          }

          // ======================================================
          // IMPORTANTE:
          //
          // A ETAPA 2 será executada nessa página.
          //
          // Primeiro vamos confirmar que a navegação automática
          // chegou corretamente aqui.
          // ======================================================

          return;
        }

        _analisarPaginaAtual(url);
      });

      // ==========================================================
      // HISTÓRICO
      // ==========================================================

      _historySubscription = _controller.historyChanged.listen((history) {
        debugPrint(
          '[E-Desk] Histórico '
          'voltar=${history.canGoBack} '
          'avançar=${history.canGoForward}',
        );

        if (mounted) {
          setState(() {});
        }
      });

      // ==========================================================
      // CARREGAMENTO
      // ==========================================================

      _loadingSubscription = _controller.loadingState.listen((state) {
        if (!mounted) return;

        setState(() {
          _carregando = state == LoadingState.loading;
        });

        if (state == LoadingState.navigationCompleted) {
          _iniciarAnalisePagina();
        }
      });

      // ==========================================================
      // ABRE E-DESK
      // ==========================================================

      await _controller.loadUrl(_urlEdesk);

      if (!mounted) return;

      setState(() {
        _inicializado = true;
        _carregando = false;
        _status = 'Aguardando E-Desk...';
      });

      debugPrint('[E-Desk] WebView inicializado.');
    } catch (e, stack) {
      debugPrint(
        '[E-Desk] ERRO AO INICIALIZAR WEBVIEW: $e',
      );

      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _erro = e.toString();
        _inicializado = false;
        _carregando = false;
      });
    }
  }

  // ============================================================
  // ANALISA URL ATUAL
  // ============================================================

  void _analisarPaginaAtual(String url) {
    if (widget.solicitacao == null || widget.solicitacao!.trim().isEmpty) {
      return;
    }

    if (widget.idTrabalho == null || widget.idTrabalho!.trim().isEmpty) {
      return;
    }

    // Lista de solicitações
    if (url.contains('/Portal/ListaSolicitacao.aspx')) {
      if (!_procurandoSolicitacao) {
        _procurandoSolicitacao = true;

        if (mounted) {
          setState(() {
            _status = 'Procurando solicitação ${widget.solicitacao}...';
          });
        }

        _iniciarAnalisePagina();
      }

      return;
    }

    // Página de solicitação
    if (url.contains('/Portal/Solicitacao.aspx')) {
      if (!_procurandoTrabalho) {
        _procurandoTrabalho = true;

        if (mounted) {
          setState(() {
            _status = 'Procurando trabalho ${widget.idTrabalho}...';
          });
        }

        _iniciarAnalisePagina();
      }
    }
  }

  // ============================================================
  // AGUARDA A PÁGINA TERMINAR DE CARREGAR
  // ============================================================

  void _iniciarAnalisePagina() {
    _automacaoTimer?.cancel();

    _automacaoTimer = Timer(
      const Duration(milliseconds: 800),
      () async {
        await _executarAutomacao();
      },
    );
  }

  // ============================================================
  // EXECUTA JAVASCRIPT
  // ============================================================

  Future<String> _executarScript(String script) async {
    try {
      final resultado = await _controller.executeScript(script);

      debugPrint(
        '[E-Desk] JavaScript retornou: $resultado',
      );

      return resultado.toString();
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro executeScript: $e',
      );

      return '';
    }
  }
  // ============================================================
  // AUTOMAÇÃO
  // ============================================================

  Future<void> _executarAutomacao() async {
    if (!mounted) return;

    final url = _currentUrl;

    if (url.isEmpty) return;

    // ==========================================================
    // NÃO FAZER NADA SE JÁ ESTAMOS NO TRABALHO
    // ==========================================================

    if (url.contains('/Portal/Trabalho.aspx') && url.contains('id_trabalho=')) {
      return;
    }

    // ==========================================================
    // ETAPA 1A
    // LOCALIZAR SOLICITAÇÃO
    // ==========================================================

    if (url.contains('/Portal/ListaSolicitacao.aspx')) {
      await _localizarSolicitacao();
      return;
    }

    // ==========================================================
    // ETAPA 1B
    // LOCALIZAR TRABALHO
    // ==========================================================

    if (url.contains('/Portal/Solicitacao.aspx')) {
      await _localizarTrabalho();
      return;
    }
  }

  // ============================================================
  // LOCALIZA SOLICITAÇÃO
  // ============================================================

  Future<void> _localizarSolicitacao() async {
    final solicitacao = widget.solicitacao?.trim() ?? '';

    if (solicitacao.isEmpty) return;

    if (!mounted) return;

    setState(() {
      _status = 'Localizando solicitação $solicitacao...';
    });

    debugPrint(
      '[E-Desk] Procurando solicitação: $solicitacao',
    );

    final script = '''
(function() {
  const alvo = ${jsonEncode(solicitacao)};

  function normalizar(v) {
    return (v || '')
      .replace(/\\\\s+/g, ' ')
      .trim();
  }

  const elementos = Array.from(
    document.querySelectorAll('a, button, input, td, span, div')
  );

  for (const el of elementos) {
    const texto = normalizar(
      el.innerText ||
      el.textContent ||
      el.value ||
      el.getAttribute('title') ||
      ''
    );

    if (!texto) continue;

    if (texto === alvo ||
        texto.includes(alvo)) {

      let clicavel = el;

      if (el.tagName !== 'A' &&
          el.tagName !== 'BUTTON') {
        clicavel =
          el.closest('a, button') || el;
      }

      const href =
        clicavel.getAttribute
          ? clicavel.getAttribute('href')
          : null;

      return JSON.stringify({
        encontrado: true,
        texto: texto,
        href: href || ''
      });
    }
  }

  return JSON.stringify({
    encontrado: false
  });
})();
''';

    final resultado = await _executarScript(script);

    debugPrint(
      '[E-Desk] Resultado solicitação: $resultado',
    );

    if (resultado.isEmpty) return;

    try {
      final dados = jsonDecode(resultado);

      if (dados is! Map) return;

      final encontrado = dados['encontrado'] == true;

      if (!encontrado) {
        debugPrint(
          '[E-Desk] Solicitação ainda não encontrada.',
        );

        return;
      }

      debugPrint(
        '[E-Desk] Solicitação encontrada: '
        '${dados['texto']}',
      );

      // ========================================================
      // CLICA NO ELEMENTO QUE CONTÉM A SOLICITAÇÃO
      // ========================================================

      final scriptClique = '''
(function() {
  const alvo = ${jsonEncode(solicitacao)};

  function normalizar(v) {
    return (v || '')
      .replace(/\\\\s+/g, ' ')
      .trim();
  }

  const elementos = Array.from(
    document.querySelectorAll('a, button, td, span, div')
  );

  for (const el of elementos) {
    const texto = normalizar(
      el.innerText ||
      el.textContent ||
      el.value ||
      ''
    );

    if (!texto) continue;

    if (texto === alvo ||
        texto.includes(alvo)) {

      let clicavel =
        el.closest('a, button');

      if (!clicavel) {
        clicavel = el;
      }

      clicavel.click();

      return 'CLICK_OK';
    }
  }

  return 'CLICK_NAO_ENCONTRADO';
})();
''';

      final clique = await _executarScript(scriptClique);

      debugPrint(
        '[E-Desk] Clique solicitação: $clique',
      );

      if (mounted) {
        setState(() {
          _status = 'Solicitação encontrada. Abrindo...';
        });
      }
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro processando solicitação: $e',
      );
    }
  }

  // ============================================================
  // LOCALIZA TRABALHO
  // ============================================================

  Future<void> _localizarTrabalho() async {
    final idTrabalho = widget.idTrabalho?.trim() ?? '';

    if (idTrabalho.isEmpty) return;

    if (!mounted) return;

    setState(() {
      _status = 'Localizando trabalho $idTrabalho...';
    });

    debugPrint(
      '[E-Desk] Procurando trabalho: $idTrabalho',
    );

    final script = '''
(function() {
  const alvo = ${jsonEncode(idTrabalho)};

  function normalizar(v) {
    return (v || '')
      .replace(/\\\\s+/g, ' ')
      .trim();
  }

  const elementos = Array.from(
    document.querySelectorAll('a, button, input, td, span, div')
  );

  for (const el of elementos) {
    const texto = normalizar(
      el.innerText ||
      el.textContent ||
      el.value ||
      el.getAttribute('title') ||
      ''
    );

    if (!texto) continue;

    if (texto === alvo ||
        texto.includes(alvo)) {

      let clicavel = el;

      if (el.tagName !== 'A' &&
          el.tagName !== 'BUTTON') {
        clicavel =
          el.closest('a, button') || el;
      }

      const href =
        clicavel.getAttribute
          ? clicavel.getAttribute('href')
          : null;

      return JSON.stringify({
        encontrado: true,
        texto: texto,
        href: href || ''
      });
    }
  }

  return JSON.stringify({
    encontrado: false
  });
})();
''';

    final resultado = await _executarScript(script);

    debugPrint(
      '[E-Desk] Resultado trabalho: $resultado',
    );

    if (resultado.isEmpty) return;

    try {
      final dados = jsonDecode(resultado);

      if (dados is! Map) return;

      final encontrado = dados['encontrado'] == true;

      if (!encontrado) {
        debugPrint(
          '[E-Desk] Trabalho ainda não encontrado.',
        );

        return;
      }

      debugPrint(
        '[E-Desk] Trabalho encontrado: '
        '${dados['texto']}',
      );

      // ========================================================
      // CLICA NO TRABALHO
      // ========================================================

      final scriptClique = '''
(function() {
  const alvo = ${jsonEncode(idTrabalho)};

  function normalizar(v) {
    return (v || '')
      .replace(/\\\\s+/g, ' ')
      .trim();
  }

  const elementos = Array.from(
    document.querySelectorAll('a, button, td, span, div')
  );

  for (const el of elementos) {
    const texto = normalizar(
      el.innerText ||
      el.textContent ||
      el.value ||
      ''
    );

    if (!texto) continue;

    if (texto === alvo ||
        texto.includes(alvo)) {

      let clicavel =
        el.closest('a, button');

      if (!clicavel) {
        clicavel = el;
      }

      clicavel.click();

      return 'CLICK_OK';
    }
  }

  return 'CLICK_NAO_ENCONTRADO';
})();
''';

      final clique = await _executarScript(scriptClique);

      debugPrint(
        '[E-Desk] Clique trabalho: $clique',
      );

      if (mounted) {
        setState(() {
          _status = 'Trabalho $idTrabalho encontrado. Abrindo...';
        });
      }
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro processando trabalho: $e',
      );
    }
  }

  // ============================================================
  // VOLTAR
  // ============================================================

  Future<void> _voltar() async {
    try {
      await _controller.goBack();
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro ao voltar: $e',
      );
    }
  }

  // ============================================================
  // AVANÇAR
  // ============================================================

  Future<void> _avancar() async {
    try {
      await _controller.goForward();
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro ao avançar: $e',
      );
    }
  }

  // ============================================================
  // RECARREGAR
  // ============================================================

  Future<void> _recarregar() async {
    try {
      await _controller.reload();
    } catch (e) {
      debugPrint(
        '[E-Desk] Erro ao recarregar: $e',
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _automacaoTimer?.cancel();

    _urlSubscription?.cancel();
    _historySubscription?.cancel();
    _loadingSubscription?.cancel();

    _controller.dispose();

    super.dispose();
  }

  // ============================================================
  // TELA
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('E-Desk'),
        actions: [
          IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: _currentUrl.isEmpty ? null : _voltar,
          ),
          IconButton(
            tooltip: 'Avançar',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _avancar,
          ),
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: _recarregar,
          ),
        ],
      ),
      body: _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 50,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Não foi possível abrir o E-Desk.',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppPalette.secondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _erro = null;
                          _carregando = true;
                          _inicializado = false;
                          _status = 'Tentando novamente...';
                        });

                        _inicializar();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text(
                        'Tentar novamente',
                      ),
                    ),
                  ],
                ),
              ),
            )
          : !_inicializado
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Webview(
                        _controller,
                      ),
                    ),

                    if (_carregando)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(),
                      ),

                    // ==================================================
                    // STATUS DA AUTOMAÇÃO
                    // ==================================================

                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _trabalhoEncontrado
                                  ? Colors.green
                                  : AppPalette.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _trabalhoEncontrado
                                    ? Icons.check_circle
                                    : Icons.sync,
                                size: 18,
                                color: _trabalhoEncontrado
                                    ? Colors.green
                                    : AppPalette.secondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _status,
                                  style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
