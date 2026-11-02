import 'dart:async';
import 'package:flutter/material.dart';

class IntegrationReadinessPanel extends StatefulWidget {
  const IntegrationReadinessPanel(
      {super.key,
      required this.check,
      required this.allowed,
      this.disabled = false});
  final Future<Map<String, dynamic>> Function() check;
  final bool Function() allowed;
  final bool disabled;
  @override
  State<IntegrationReadinessPanel> createState() =>
      _IntegrationReadinessPanelState();
}

class _IntegrationReadinessPanelState extends State<IntegrationReadinessPanel> {
  bool _checking = false;
  String _message =
      'Verifique a integra\u00e7\u00e3o deste computador antes de buscar.';
  Future<void> _check() async {
    if (_checking || widget.disabled || !widget.allowed()) return;
    setState(() => _checking = true);
    try {
      final health = await widget.check().timeout(const Duration(seconds: 12));
      if (!mounted || !widget.allowed()) return;
      final version = RegExp(r'(\d+)$')
          .firstMatch('${health['integrationPackageVersion'] ?? ''}')
          ?.group(1);
      final suffix = version == null ? '' : ' \u00b7 v$version';
      setState(() => _message = health['service'] != 'gerenciador-horas-edesk'
          ? 'Servi\u00e7o n\u00e3o reconhecido. Abra a integra\u00e7\u00e3o E-Desk.'
          : health['mode'] == 'files-only'
              ? 'Somente arquivos conectados. Inicie a integra\u00e7\u00e3o E-Desk completa.'
              : health['busy'] == true
                  ? 'Integra\u00e7\u00e3o ocupada. Aguarde a opera\u00e7\u00e3o atual.$suffix'
                  : health['workGridImport'] != true ||
                          health['requestTitleImport'] != true
                      ? 'Atualize a integra\u00e7\u00e3o para importar os trabalhos pelo ID.$suffix'
                      : 'Integra\u00e7\u00e3o pronta para importar.$suffix');
    } catch (_) {
      if (mounted && widget.allowed()) {
        setState(() => _message =
            'Sem resposta. Inicie a integra\u00e7\u00e3o e confira a permiss\u00e3o de rede local do navegador.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
                onPressed: _checking || widget.disabled ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link, size: 18),
                label: const Text('Verificar integra\u00e7\u00e3o')),
            Text(_message,
                key: const ValueKey('import-integration-status'),
                style: Theme.of(context).textTheme.bodySmall),
          ]));
}
