Future<EdeskPythonResult> executarPythonEdesk({
  required String requestJson,
  required bool enviar,
  String script = 'edesk_comentario.py',
  bool speakResult = false,
}) async {
  return _resultadoIndisponivel(script);
}

Future<EdeskPythonResult> executarPythonEdeskBackground({
  required String requestJson,
  required bool enviar,
  String script = 'edesk_fases.py',
}) async {
  return _resultadoIndisponivel(script);
}

EdeskPythonResult _resultadoIndisponivel(String script) {
  return EdeskPythonResult(
    confirmed: false,
    statusCode: 0,
    message: 'A automação E-Desk ($script) depende de Python e Chromium '
        'locais e não pode ser executada diretamente no navegador. '
        'É necessário configurar um serviço de automação hospedado.',
    responseBody: '',
  );
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
