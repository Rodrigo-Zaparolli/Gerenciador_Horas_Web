import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/services/native_local_files_service.dart';

void showLocalFileError(BuildContext context, Object error,
    {required String resource}) {
  final setup = error is NativeFilesException && error.needsSetup;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Não foi possível abrir $resource: $error'),
    duration: Duration(seconds: setup ? 12 : 6),
    action: setup
        ? SnackBarAction(
            label: 'Configurar',
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => const LocalFileSetupDialog()))
        : null,
  ));
}

class LocalFileSetupDialog extends StatelessWidget {
  const LocalFileSetupDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Abrir arquivos neste computador'),
        content: const SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Text(
                    'A integração precisa estar instalada e ativa em cada PC que abre pastas ou planilhas locais.\n\n'
                    '1. Abra a configuração abaixo e baixe a integração completa.\n'
                    '2. Use Extrair tudo e execute Iniciar integração E-Desk.cmd na pasta extraída.\n'
                    '3. Clique em Verificar conexão e permita o acesso à rede local ou a este dispositivo, se o navegador solicitar.\n'
                    '4. Volte ao app e tente abrir novamente.\n\n'
                    'Se já instalou o pacote neste PC, basta iniciar a integração. Nas versões atuais ela inicia automaticamente com o Windows, se essa opção estiver ativada.'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar')),
          FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir configuração'),
              onPressed: () async {
                try {
                  final opened = await launchUrl(
                      Uri.parse(
                          'https://gerenciador-horas.web.app/integracao-completa.html'),
                      mode: LaunchMode.externalApplication);
                  if (!opened) throw StateError('Página indisponível');
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Abra gerenciador-horas.web.app/integracao-completa.html no navegador deste PC.')));
                  }
                }
              }),
        ],
      );
}
