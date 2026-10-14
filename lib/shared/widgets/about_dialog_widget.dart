import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
// ignore_for_file: unnecessary_cast
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Função pública para exibir o diálogo "Sobre o Desenvolvedor" e verificação de atualizações
void showCustomAuthorDialog(BuildContext context) async {
  // Pega a versão atual do app instalada no dispositivo em tempo real
  String currentVersion = '1.0.0';
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    currentVersion = packageInfo.version;
  } catch (e) {
    // Mantém o padrão caso ocorra algum erro
  }

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (context) {
      AppAppearance.watch(context);
      return AlertDialog(
        backgroundColor: AppPalette.surface, // Padrão de cor do seu app
        /*title: const Text(
          'Sobre o Desenvolvedor',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),*/
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sistema desenvolvido por:',
              style: TextStyle(color: AppPalette.secondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Rodrigo Zaparolli',
              style: TextStyle(
                color: AppPalette.accent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Versão atual: $currentVersion',
              style: TextStyle(color: AppPalette.secondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          /* 
          // BOTÃO DE VERIFICAR ATUALIZAÇÕES COMENTADO TEMPORARIAMENTE
          // Para reativar no futuro, basta descomentar este bloco e a função abaixo.
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.accent,
            ),
            onPressed: () {
              Navigator.pop(context); // Fecha o dialog sobre
              _checkForUpdatesFromDialog(
                  context, currentVersion); // Roda a checagem
            },
            icon: const Icon(Icons.system_update, size: 18),
            label: const Text('Verificar Atualizações'),
          ),
          */
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: AppPalette.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    },
  );
}

/* 
// ============================================================
// FUNÇÃO DE CHECAGEM COMENTADA PARA USO FUTURO
// ============================================================
Future<void> _checkForUpdatesFromDialog(
    BuildContext context, String currentVersion) async {
  // Mostra um indicador de carregamento rápido
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: AppPalette.accent),
    ),
  );

  try {
    // URL corrigida (sem parênteses extras e com timeout de segurança)
    final response = await http
        .get(
          Uri.parse(
              'https://raw.githubusercontent.com/Rodrigo-Zaparolli/Gerenciador_Horas/main/version.json'),
        )
        .timeout(const Duration(seconds: 10));

    // Fecha o indicador de carregamento
    if (context.mounted) Navigator.pop(context);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String latestVersion = data['version'];
      final String installerUrl = data['installerUrl'];

      if (!context.mounted) return;

      if (latestVersion != currentVersion) {
        // Se houver versão nova, mostra o aviso para baixar
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppPalette.surface,
            title: const Text('Nova Atualização Disponível!',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'A versão $latestVersion está disponível para download.',
              style: const TextStyle(color: AppPalette.secondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.accent),
                onPressed: () async {
                  Navigator.pop(context);
                  final Uri url = Uri.parse(installerUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Baixar Agora',
                    style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      } else {
        // Se já estiver na última versão
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seu aplicativo já está na versão mais recente!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      throw Exception('Erro ao carregar versão');
    }
  } catch (e) {
    // Fecha o carregamento caso dê erro de rede ou timeout
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Não foi possível verificar as atualizações. Verifique sua conexão.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
*/
