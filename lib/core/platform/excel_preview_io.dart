import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

Future<String> renderLocalExcel(String caminho, String intervalo) async {
  if (!await File(caminho).exists()) {
    throw StateError('Arquivo Excel não encontrado: $caminho');
  }
  Process? processo;
  try {
    // =============================================================
    // PYTHON
    //
    // IMPORTANTE:
    // O openpyxl foi confirmado neste Python 3.14.
    // Não usamos mais a .venv antiga para o Excel Preview.
    // =============================================================

    // Resolve os caminhos do Excel Preview sem depender do caminho
    // fixo da máquina de desenvolvimento. No aplicativo instalado,
    // os arquivos ficam ao lado do executável. Durante o desenvolvimento,
    // também aceitamos os caminhos do projeto e o Python local já usado.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final projetoDir = Directory.current.path;
    final localAppData = Platform.environment['LOCALAPPDATA'];

    String? primeiroArquivoExistente(List<String> candidatos) {
      for (final candidato in candidatos) {
        if (candidato.trim().isNotEmpty && File(candidato).existsSync()) {
          return candidato;
        }
      }
      return null;
    }

    final candidatosPython = <String>[
      '$exeDir\\python\\python.exe',
      '$exeDir\\python\\Scripts\\python.exe',
      '$projetoDir\\python\\python.exe',
      '$projetoDir\\python\\Scripts\\python.exe',
      '$projetoDir\\.venv\\Scripts\\python.exe',
      if (localAppData != null && localAppData.trim().isNotEmpty)
        '$localAppData\\Python\\pythoncore-3.14-64\\python.exe',
    ];

    final candidatosScript = <String>[
      '$exeDir\\edesk_bot\\excel_preview.py',
      '$projetoDir\\edesk_bot\\excel_preview.py',
    ];

    final pythonExe = primeiroArquivoExistente(candidatosPython);
    final scriptExcel = primeiroArquivoExistente(candidatosScript);

    if (pythonExe == null) {
      throw Exception(
        'Python não encontrado para o Excel Preview.\n'
        'Caminhos verificados:\n${candidatosPython.join('\n')}',
      );
    }

    if (scriptExcel == null) {
      throw Exception(
        'Script excel_preview.py não encontrado.\n'
        'Caminhos verificados:\n${candidatosScript.join('\n')}',
      );
    }

    final pythonFile = File(pythonExe);
    final scriptFile = File(scriptExcel);

    // =============================================================
    // CONFERE OS ARQUIVOS
    // =============================================================

    if (!await pythonFile.exists()) {
      throw Exception(
        'Python 3.14 não encontrado:\n$pythonExe',
      );
    }

    if (!await scriptFile.exists()) {
      throw Exception(
        'Script excel_preview.py não encontrado:\n$scriptExcel',
      );
    }

    debugPrint('');
    debugPrint('==============================================');
    debugPrint('[ExcelPreview] INICIANDO PREVIEW');
    debugPrint('==============================================');
    debugPrint('[ExcelPreview] Python: $pythonExe');
    debugPrint('[ExcelPreview] Script: $scriptExcel');
    debugPrint('[ExcelPreview] Excel: $caminho');
    debugPrint('[ExcelPreview] Intervalo: $intervalo');

    // =============================================================
    // INICIA O PYTHON
    // =============================================================

    processo = await Process.start(
      pythonExe,
      [
        '-u',
        scriptExcel,
      ],
      runInShell: false,
    );

    debugPrint(
      '[ExcelPreview] Processo iniciado. PID: ${processo.pid}',
    );

    // =============================================================
    // STDERR
    // =============================================================

    final stderrBuffer = StringBuffer();

    processo.stderr
        .transform(
          const Utf8Decoder(
            allowMalformed: true,
          ),
        )
        .transform(
          const LineSplitter(),
        )
        .listen(
      (linha) {
        final texto = linha.trim();

        if (texto.isEmpty) {
          return;
        }

        stderrBuffer.writeln(texto);

        debugPrint(
          '[excel_preview.py] $texto',
        );
      },
      onError: (erro) {
        debugPrint(
          '[ExcelPreview] Erro ao ler STDERR: $erro',
        );
      },
    );

    // =============================================================
    // PREPARA A RESPOSTA
    // =============================================================

    final respostaCompleter = Completer<Map<String, dynamic>>();

    processo.stdout
        .transform(
          const Utf8Decoder(
            allowMalformed: true,
          ),
        )
        .transform(
          const LineSplitter(),
        )
        .listen(
      (linha) {
        final texto = linha.trim();

        if (texto.isEmpty) {
          return;
        }

        debugPrint(
          '[excel_preview.py stdout] $texto',
        );

        try {
          final decoded = jsonDecode(texto);

          if (decoded is Map) {
            final resposta = Map<String, dynamic>.from(decoded);

            if (!respostaCompleter.isCompleted) {
              respostaCompleter.complete(resposta);
            }
          }
        } catch (_) {
          // Ignora qualquer saída que não seja JSON.
        }
      },
      onError: (erro) {
        if (!respostaCompleter.isCompleted) {
          respostaCompleter.completeError(
            Exception(
              'Erro ao ler resposta do excel_preview.py: $erro',
            ),
          );
        }
      },
      onDone: () {
        if (!respostaCompleter.isCompleted) {
          final erroPython = stderrBuffer.toString().trim();

          if (erroPython.isNotEmpty) {
            respostaCompleter.completeError(
              Exception(
                'excel_preview.py foi encerrado sem retornar '
                'uma resposta válida.\n\n$erroPython',
              ),
            );
          } else {
            respostaCompleter.completeError(
              Exception(
                'excel_preview.py foi encerrado sem retornar '
                'uma resposta válida.',
              ),
            );
          }
        }
      },
    );

    // =============================================================
    // ENVIA COMANDO PARA O PYTHON
    // =============================================================

    final comando = jsonEncode({
      'acao': 'open',
      'path': caminho,
      'intervalo': intervalo,
    });

    debugPrint(
      'Excel preview -> arquivo: $caminho',
    );

    debugPrint(
      'Excel preview -> intervalo: $intervalo',
    );

    processo.stdin.writeln(comando);

    await processo.stdin.flush();

    // =============================================================
    // AGUARDA A RESPOSTA
    // =============================================================

    final resposta = await respostaCompleter.future.timeout(
      const Duration(
        seconds: 30,
      ),
      onTimeout: () {
        throw TimeoutException(
          'O excel_preview.py não respondeu em 30 segundos.',
        );
      },
    );

    // =============================================================
    // VALIDA RETORNO
    // =============================================================

    if (resposta['ok'] != true) {
      final mensagem = resposta['erro']?.toString().trim() ??
          resposta['message']?.toString().trim() ??
          'Erro desconhecido ao gerar a imagem do Excel.';

      throw Exception(mensagem);
    }

    // =============================================================
    // RECEBE BASE64
    // =============================================================

    final base64Recebido = resposta['imagemBase64']?.toString().trim() ?? '';

    if (base64Recebido.isEmpty) {
      throw Exception(
        'O excel_preview.py não retornou a imagem '
        'do intervalo $intervalo.',
      );
    }

    return base64Recebido;
  } finally {
    // =============================================================
    // ENCERRA O PYTHON
    // =============================================================

    if (processo != null) {
      try {
        processo.stdin.writeln(
          jsonEncode({
            'acao': 'close',
          }),
        );

        await processo.stdin.flush();
      } catch (_) {
        // Processo já pode ter sido encerrado.
      }

      try {
        await processo.stdin.close();
      } catch (_) {
        // Ignora.
      }

      try {
        processo.kill();
      } catch (_) {
        // Ignora.
      }
    }
  }
}
