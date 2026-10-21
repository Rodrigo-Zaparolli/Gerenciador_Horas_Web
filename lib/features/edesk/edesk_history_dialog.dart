import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/edesk_operation_history.dart';
import '../../data/services/edesk_integration.dart';
import '../../shared/widgets/recovery_error.dart';

Future<void> showEdeskHistory(BuildContext context) => showDialog<void>(
    context: context, builder: (_) => const EdeskHistoryDialog());

class EdeskHistoryDialog extends StatefulWidget {
  const EdeskHistoryDialog({super.key, this.owner, this.accountLoader, this.ledgerLoader, this.isCurrentAccount});
  final String? owner;
  final Future<List<Map<String, dynamic>>> Function(String)? accountLoader;
  final Future<Map<String, dynamic>> Function()? ledgerLoader;
  final bool Function()? isCurrentAccount;
  @override
  State<EdeskHistoryDialog> createState() => _EdeskHistoryDialogState();
}

class _EdeskHistoryDialogState extends State<EdeskHistoryDialog> {
  late final String? uid;
  bool get sameAccount => widget.isCurrentAccount?.call() ?? FirebaseAuth.instance.currentUser?.uid == uid;
  int page = 0;
  String filter = 'all', message = '';
  bool busy = false;
  Map<String, dynamic> ledger = {};
  List<Map<String, dynamic>> accountItems = [];
  @override
  void initState() {
    super.initState();
    uid = widget.owner ?? FirebaseAuth.instance.currentUser?.uid;
    refresh();
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    String accountError = '';
    try {
      if (uid != null) {
        accountItems = await (widget.accountLoader ?? EdeskOperationHistory.loadAccount)(uid!);
      }
    } catch (error) {
      accountError =
          'Histórico da conta indisponível; mostrando a cópia deste dispositivo. ';
    }
    try {
      final result = await (widget.ledgerLoader?.call() ?? EdeskIntegrationApi.call('/api/edesk/history'));
      if (!mounted || !sameAccount) return;
      ledger = Map<String, dynamic>.from(result['items'] as Map? ?? {});
      message = accountError;
    } catch (error) {
      message = recoveryError(error,
          operation: 'consultar o histórico da integração');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final merged = EdeskOperationHistory.combine(accountItems, EdeskOperationHistory.read(uid));
    final items = sameAccount
        ? merged
            .where((e) =>
                filter == 'all' ||
                e['state'] != 'confirmed' && e['state'] != 'tested')
            .toList()
        : <Map<String, dynamic>>[];
    items.sort((a, b) => (b['created']?.toString() ?? '')
        .compareTo(a['created']?.toString() ?? ''));
    final lastPage = ((items.length + 11) ~/ 12).clamp(1, 999) - 1;
    if (page > lastPage) page = lastPage;
    final visible = items.skip(page * 12).take(12);
    return AlertDialog(
      title: const Text('Histórico de envios ao E-Desk'),
      content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                const Text(
                    'Operações registradas a partir desta atualização, com até 200 recentes da conta e uma cópia local. Não reenvie resultados incertos sem conferir no E-Desk.'),
                const SizedBox(height: 12),
                if (busy) const LinearProgressIndicator(),
                if (message.isNotEmpty) Text(message),
                if (sameAccount && EdeskOperationHistory.pendingSync(uid) > 0)
                  Text('${EdeskOperationHistory.pendingSync(uid)} registro(s) aguardando sincronização com a conta. O envio ao E-Desk não será repetido.'),
                if (sameAccount && ledger.isNotEmpty)
                  Text(
                      'Histórico de proteção da integração: ${ledger.values.where((v) => v == 'confirmed').length} horas confirmadas; ${ledger.values.where((v) => v == 'pending' || v == 'uncertain').length} para conferir.'),
                DropdownButton<String>(
                    isExpanded: true,
                    value: filter,
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('Todas as operações', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: 'review',
                          child: Text('Precisam de conferência', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => setState(() {
                          filter = value!;
                          page = 0;
                        })),
                if (items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhuma operação neste filtro.')),
                for (final item in visible)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${item['action']} · Solicitação ${item['project']}'),
                    subtitle: Text(
                        '${_date(item['created'] as String?)}\n${EdeskOperationHistory.label(item['state'] as String? ?? '')}'),
                    isThreeLine: true,
                  ),
                Row(children: [
                  IconButton(
                      tooltip: 'Página anterior',
                      onPressed:
                          page == 0 ? null : () => setState(() => page--),
                      icon: const Icon(Icons.chevron_left)),
                  Text(
                      '${page + 1} / ${((items.length + 11) ~/ 12).clamp(1, 999)}'),
                  IconButton(
                      tooltip: 'Próxima página',
                      onPressed: (page + 1) * 12 >= items.length
                          ? null
                          : () => setState(() => page++),
                      icon: const Icon(Icons.chevron_right)),
                ]),
              ]))),
      actions: [
        TextButton(
            onPressed: busy ? null : refresh,
            child: const Text('Verificar novamente')),
        TextButton(
            onPressed: () => launchUrl(
                Uri.parse('https://promob.e-desk.com.br/'),
                mode: LaunchMode.externalApplication),
            child: const Text('Abrir E-Desk')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }

  String _date(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    return date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
