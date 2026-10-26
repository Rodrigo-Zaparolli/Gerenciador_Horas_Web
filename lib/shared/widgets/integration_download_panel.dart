import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/integration_downloads.dart';

class IntegrationDownloadPanel extends StatefulWidget {
  const IntegrationDownloadPanel(
      {super.key, required this.downloads, this.openDownload});
  final IntegrationDownloads downloads;
  final Future<bool> Function(Uri)? openDownload;
  @override
  State<IntegrationDownloadPanel> createState() =>
      _IntegrationDownloadPanelState();
}

class _IntegrationDownloadPanelState extends State<IntegrationDownloadPanel> {
  bool busy = false;
  String? error;
  Future<void> download(String path) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final uri = Uri.base.resolve(path);
      final opened = await (widget.openDownload?.call(uri) ??
          launchUrl(uri, webOnlyWindowName: '_blank'));
      if (!opened) throw StateError('Download não iniciado.');
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Não foi possível iniciar o download. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Integração E-Desk v${widget.downloads.version}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'Se já usa esta versão da integração, basta atualizar o app.'),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                      key: const ValueKey('download-integration-update'),
                      onPressed: busy
                          ? null
                          : () => download(widget.downloads.updatePath),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar atualização leve')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      key: const ValueKey('download-integration-complete'),
                      onPressed: busy
                          ? null
                          : () => download(widget.downloads.completePath),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar instalação completa')),
                  const SizedBox(height: 8),
                  const Text(
                      'Para atualizar a integração: aguarde os envios terminarem, pare a integração, extraia o ZIP na pasta atual e inicie novamente.'),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ])),
      );
}
