import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/services/edesk_endpoint.dart';
import '../../data/services/edesk_integration.dart';

class EdeskCentralDialog extends StatefulWidget {
  const EdeskCentralDialog({super.key, this.settings, this.uidProvider});
  final EdeskEndpointSettings? settings;
  final String? Function()? uidProvider;
  @override
  State<EdeskCentralDialog> createState() => _EdeskCentralDialogState();
}

class _EdeskCentralDialogState extends State<EdeskCentralDialog> {
  EdeskEndpointSettings get settings =>
      widget.settings ?? edeskEndpointSettings;
  String? get uid => widget.uidProvider != null
      ? widget.uidProvider!()
      : FirebaseAuth.instance.currentUser?.uid;
  final address = TextEditingController();
  final account = TextEditingController();
  bool central = false, busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    address.dispose();
    account.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final url = await settings.currentUrl(refresh: true);
      if (!mounted) return;
      central = url != normalizeEdeskUrl(defaultEdeskApiUrl);
      address.text = central ? url : '';
    } catch (_) {
      message = 'Não foi possível carregar a configuração da conta.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        message = error
            .toString()
            .replaceFirst(RegExp(r'^(Bad state|FormatException): '), '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pair() => perform(() async {
        final owner = uid;
        final result = await EdeskIntegrationApi.call('/api/edesk/central/pair',
            baseUrl: 'http://127.0.0.1:8765', body: {});
        final url = normalizeEdeskUrl(result['url'] as String? ?? '');
        if (uid != owner)
          throw StateError('A conta mudou. Abra a configuração novamente.');
        await settings.save(centralUrl: url);
        if (!mounted) return;
        central = true;
        address.text = url;
        message =
            'Computador central autorizado. A mesma conta usará este endereço nos outros PCs.';
      });

  Future<void> save() => perform(() async {
        final owner = uid;
        if (central) {
          final url = normalizeEdeskUrl(address.text);
          final health = await EdeskIntegrationApi.call('/healthz',
              authenticated: false, baseUrl: url);
          if (health['service'] != 'gerenciador-horas-edesk' ||
              health['status'] != 'ok') {
            throw StateError('O endereço não corresponde à integração E-Desk.');
          }
          final session = await EdeskIntegrationApi.call('/api/edesk/session',
              baseUrl: url);
          if (session['authorized'] != true)
            throw StateError('Esta conta não está autorizada na central.');
          if (uid != owner)
            throw StateError('A conta mudou. Abra a configuração novamente.');
          await settings.save(centralUrl: url);
        } else {
          await settings.save();
        }
        if (mounted)
          message =
              'Configuração salva para esta conta. Nenhum envio foi realizado.';
      });

  Future<void> authorize() => perform(() async {
        final owner = this.uid;
        final uid = account.text.trim();
        if (uid.isEmpty || uid.length > 128)
          throw StateError('Informe o ID da conta a autorizar.');
        final url = normalizeEdeskUrl(address.text);
        final existing = await EdeskIntegrationApi.call(
            '/api/edesk/central/access',
            baseUrl: url);
        final users = (existing['users'] as List).cast<String>().toSet()
          ..add(uid);
        if (this.uid != owner)
          throw StateError('A conta mudou. Abra a configuração novamente.');
        await EdeskIntegrationApi.call('/api/edesk/central/access',
            baseUrl: url, body: {'users': users.toList()});
        if (mounted) {
          account.clear();
          message =
              'Conta autorizada. Nela, configure o mesmo endereço da central.';
        }
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Configurar integração E-Desk'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                      'Somente o computador central precisa ter a integração instalada e permanecer ligado. '
                      'Os outros PCs usam o navegador na mesma rede.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                      isExpanded: true,
                      initialValue: central,
                      key: ValueKey(central),
                      decoration: const InputDecoration(
                          labelText: 'Onde executar os envios'),
                      items: const [
                        DropdownMenuItem(
                            value: false,
                            child: Text('Neste computador',
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(
                            value: true,
                            child: Text('No computador central',
                                maxLines: 1, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: busy
                          ? null
                          : (value) =>
                              setState(() => central = value ?? false)),
                  if (central) ...[
                    const SizedBox(height: 14),
                    TextField(
                        controller: address,
                        enabled: !busy,
                        decoration: const InputDecoration(
                            labelText: 'Endereço da central',
                            hintText: 'http://192.168.1.10:8765')),
                    const SizedBox(height: 8),
                    const Text(
                        'Em Chrome ou Edge, permita o acesso à rede local quando solicitado. '
                        'O endereço é salvo na nuvem para a mesma conta.'),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed: busy ? null : pair,
                      icon: const Icon(Icons.computer),
                      label: const Text('Autorizar este PC como central')),
                  const SizedBox(height: 6),
                  const Text(
                      'No PC central, execute “Iniciar central E-Desk.cmd” antes de autorizar.'),
                  const SizedBox(height: 12),
                  SelectableText('ID desta conta: ${uid ?? ""}',
                      style: const TextStyle(fontSize: 12)),
                  if (central)
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Autorizar outra conta'),
                        children: [
                          TextField(
                              controller: account,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                  labelText: 'ID da outra conta')),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                  onPressed: busy ? null : authorize,
                                  child: const Text('Autorizar conta'))),
                          const Text(
                              'Somente a conta responsável pela central pode autorizar outras contas.'),
                        ]),
                  if (busy)
                    const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator()),
                  if (message != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(message!)),
                ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Fechar')),
          FilledButton(
              onPressed: busy ? null : save,
              child: const Text('Salvar configuração'))
        ],
      );
}
