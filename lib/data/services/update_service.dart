import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// SERVIÇO DE ATUALIZAÇÃO AUTOMÁTICA
// ============================================================================

Future<void> verificarAtualizacaoAutomatica(BuildContext context) async {
  if (kIsWeb) return;

  debugPrint('============================================================');
  debugPrint('[UPDATE] Iniciando verificação de atualização...');
  debugPrint('============================================================');

  try {
    // ========================================================================
    // 1. OBTÉM A VERSÃO INSTALADA
    // ========================================================================

    debugPrint('[UPDATE] Obtendo informações do aplicativo...');

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    final String currentVersion = packageInfo.version;
    final String currentBuildNumber = packageInfo.buildNumber;

    debugPrint('[UPDATE] Nome do aplicativo: ${packageInfo.appName}');
    debugPrint('[UPDATE] Package name: ${packageInfo.packageName}');
    debugPrint('[UPDATE] Versão instalada: $currentVersion');
    debugPrint('[UPDATE] Build instalado: $currentBuildNumber');

    // ========================================================================
    // 2. URL DO ARQUIVO VERSION.JSON
    // ========================================================================

    final Uri versionUri = Uri.parse(
      'https://raw.githubusercontent.com/'
      'Rodrigo-Zaparolli/'
      'Gerenciador_Horas/'
      'main/'
      'version.json',
    );

    debugPrint('[UPDATE] Consultando version.json...');
    debugPrint('[UPDATE] URL: $versionUri');

    // ========================================================================
    // 3. CONSULTA O GITHUB
    // ========================================================================

    final http.Response response =
        await http.get(versionUri).timeout(const Duration(seconds: 10));

    debugPrint('[UPDATE] Status HTTP: ${response.statusCode}');

    // ========================================================================
    // 4. VERIFICA RESPOSTA HTTP
    // ========================================================================

    if (response.statusCode != 200) {
      debugPrint(
        '[UPDATE] ERRO: version.json retornou HTTP '
        '${response.statusCode}.',
      );

      debugPrint(
          '============================================================');
      return;
    }

    debugPrint('[UPDATE] version.json recebido com sucesso.');
    debugPrint('[UPDATE] Conteúdo recebido: ${response.body}');

    // ========================================================================
    // 5. DECODIFICA O JSON
    // ========================================================================

    final dynamic decodedData = json.decode(response.body);

    if (decodedData is! Map<String, dynamic>) {
      debugPrint(
        '[UPDATE] ERRO: o conteúdo de version.json não é um objeto JSON.',
      );

      debugPrint(
          '============================================================');
      return;
    }

    final Map<String, dynamic> data = decodedData;

    // ========================================================================
    // 6. VALIDA OS CAMPOS DO JSON
    // ========================================================================

    final dynamic versionValue = data['version'];
    final dynamic installerUrlValue = data['installerUrl'];

    if (versionValue == null || versionValue.toString().trim().isEmpty) {
      debugPrint(
        '[UPDATE] ERRO: campo "version" não encontrado '
        'ou está vazio.',
      );

      debugPrint(
          '============================================================');
      return;
    }

    if (installerUrlValue == null ||
        installerUrlValue.toString().trim().isEmpty) {
      debugPrint(
        '[UPDATE] ERRO: campo "installerUrl" não encontrado '
        'ou está vazio.',
      );

      debugPrint(
          '============================================================');
      return;
    }

    final String latestVersion = versionValue.toString().trim();
    final String installerUrl = installerUrlValue.toString().trim();

    debugPrint('[UPDATE] Versão disponível: $latestVersion');
    debugPrint('[UPDATE] Versão instalada: $currentVersion');
    debugPrint('[UPDATE] Instalador: $installerUrl');

    // ========================================================================
    // 7. VERIFICA SE O WIDGET AINDA ESTÁ MONTADO
    // ========================================================================

    if (!context.mounted) {
      debugPrint(
        '[UPDATE] Context não está mais montado. '
        'Verificação cancelada.',
      );

      debugPrint(
          '============================================================');
      return;
    }

    // ========================================================================
    // 8. COMPARAÇÃO DAS VERSÕES
    // ========================================================================
    //
    // Neste momento mantemos a mesma regra do código original:
    //
    // versão remota diferente da versão instalada = atualização disponível.
    //
    // Depois que confirmarmos o funcionamento, podemos melhorar isso para
    // uma comparação semântica:
    //
    // 1.0.2 > 1.0.1
    //
    // evitando que versões mais antigas sejam interpretadas como atualização.
    // ========================================================================

    if (latestVersion == currentVersion) {
      debugPrint('[UPDATE] Aplicativo já está atualizado.');
      debugPrint('[UPDATE] Nenhuma atualização necessária.');
      debugPrint(
          '============================================================');
      return;
    }

    debugPrint('------------------------------------------------------------');
    debugPrint('[UPDATE] ATUALIZAÇÃO DISPONÍVEL!');
    debugPrint(
      '[UPDATE] $currentVersion -> $latestVersion',
    );
    debugPrint('------------------------------------------------------------');

    // ========================================================================
    // 9. EXIBE O DIÁLOGO
    // ========================================================================

    debugPrint('[UPDATE] Tentando exibir diálogo de atualização...');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),

          // ==================================================================
          // TÍTULO
          // ==================================================================

          title: const Row(
            children: [
              Icon(
                Icons.system_update_rounded,
                color: Color(0xFF00FFCC),
                size: 24,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Atualização Disponível',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),

          // ==================================================================
          // CONTEÚDO
          // ==================================================================

          content: Text(
            'Uma nova versão ($latestVersion) do Gerenciador de Horas '
            'está disponível para download.\n\n'
            'Versão instalada: $currentVersion\n'
            'Nova versão: $latestVersion\n\n'
            'Deseja atualizar agora?',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),

          // ==================================================================
          // BOTÕES
          // ==================================================================

          actions: [
            TextButton(
              onPressed: () {
                debugPrint(
                  '[UPDATE] Usuário selecionou "Depois".',
                );

                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Depois',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFCC),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                debugPrint(
                  '[UPDATE] Usuário selecionou "Atualizar Agora".',
                );

                Navigator.of(dialogContext).pop();

                // ============================================================
                // URL DO INSTALADOR
                // ============================================================

                final Uri installerUri = Uri.parse(installerUrl);

                debugPrint(
                  '[UPDATE] Tentando abrir instalador:',
                );

                debugPrint(
                  '[UPDATE] $installerUri',
                );

                try {
                  final bool podeAbrir = await canLaunchUrl(installerUri);

                  debugPrint(
                    '[UPDATE] canLaunchUrl: $podeAbrir',
                  );

                  if (!podeAbrir) {
                    debugPrint(
                      '[UPDATE] ERRO: não foi possível abrir '
                      'a URL do instalador.',
                    );

                    return;
                  }

                  final bool abriu = await launchUrl(
                    installerUri,
                    mode: LaunchMode.externalApplication,
                  );

                  debugPrint(
                    '[UPDATE] Resultado do launchUrl: $abriu',
                  );
                } catch (e, stackTrace) {
                  debugPrint(
                    '[UPDATE] ERRO ao abrir instalador: $e',
                  );

                  debugPrint(
                    '[UPDATE] StackTrace: $stackTrace',
                  );
                }
              },
              child: const Text(
                'Atualizar Agora',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    debugPrint('[UPDATE] Diálogo de atualização encerrado.');
    debugPrint('============================================================');
  } catch (e, stackTrace) {
    // ========================================================================
    // DIAGNÓSTICO
    // ========================================================================
    //
    // Durante os testes não ocultamos a exceção.
    // Assim conseguimos identificar exatamente qualquer problema.
    // ========================================================================

    debugPrint('============================================================');
    debugPrint('[UPDATE] ERRO DURANTE A VERIFICAÇÃO');
    debugPrint('[UPDATE] $e');
    debugPrint('[UPDATE] StackTrace:');
    debugPrint('$stackTrace');
    debugPrint('============================================================');
  }
}
