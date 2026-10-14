import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EdeskWebViewTestScreen extends StatelessWidget {
  final String? solicitacao;
  final String? idTrabalho;

  const EdeskWebViewTestScreen({super.key, this.solicitacao, this.idTrabalho});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('E-Desk')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_browser, size: 48),
                const SizedBox(height: 16),
                const Text('Acesse o E-Desk em uma nova aba.'),
                if (solicitacao != null) Text('Solicitação: $solicitacao'),
                if (idTrabalho != null) Text('Trabalho: $idTrabalho'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir E-Desk'),
                  onPressed: () async {
                    try {
                      final opened = await launchUrl(
                        Uri.parse(
                            'https://promob.e-desk.com.br/Portal/ListaSolicitacao.aspx?GUID=ff841454-6398-4e36-84e5-0ce750d161a5'),
                        webOnlyWindowName: '_blank',
                      );
                      if (!opened) {
                        throw StateError('Não foi possível abrir o E-Desk.');
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Não foi possível abrir o E-Desk. Verifique se o navegador permite novas abas.')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
