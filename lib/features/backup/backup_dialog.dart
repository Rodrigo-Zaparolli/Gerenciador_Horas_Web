import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/backup_service.dart';
import 'package:gerenciador_horas/data/services/file_download.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';

Future<void> showBackupDialog(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const BackupDialog());

class BackupDialog extends StatefulWidget {
  const BackupDialog({super.key});
  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  String? owner;
  String? lastExport;
  @override
  void initState() {
    super.initState();
    try { owner = FirebaseAuth.instance.currentUser?.uid; } catch (_) { owner = null; }
    lastExport = LocalUserState.read(owner, 'backup.last')?['date'] as String?;
  }
  bool busy = false;
  String message =
      'Exporte projetos, horas, comentários, modelos e configurações da sua conta. '
      'Senhas não são incluídas. Arquivos externos e anexos são mantidos como referências; '
      'guarde também os arquivos originais.';
  BackupPlan? plan;
  void progress(String text) {
    if (mounted) setState(() => message = text);
  }

  Future<bool> save(String text, String prefix) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name =
        '${prefix}_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
    if (kIsWeb) {
      downloadBytes(fileName: name, bytes: bytes, mimeType: 'application/json');
      return true;
    }
    final path = await FilePicker.platform.saveFile(
        fileName: name, type: FileType.custom, allowedExtensions: ['json']);
    if (path == null) return false;
    await writeLocalBytes(path, bytes);
    return true;
  }

  Future<void> export() async {
    setState(() {
      busy = true;
      plan = null;
    });
    try {
      final text = await BackupService().export(progress: progress);
      final saved = await save(text, 'backup_gerenciador');
      if (saved) {
        lastExport = DateTime.now().toIso8601String();
        LocalUserState.write(owner, 'backup.last', {'date': lastExport});
      }
      final data = jsonDecode(text) as Map;
      progress(!saved
          ? 'Exportação cancelada.'
          : data['edeskHistory'] == null
              ? 'Backup dos dados da conta exportado. O histórico local de envios não pôde ser incluído. '
                  'Inicie a integração E-Desk e exporte novamente para incluí-lo.'
              : 'Backup exportado, incluindo o histórico local de envios ao E-Desk.');
    } catch (error) {
      progress(recoveryError(error, operation: 'exportar o backup'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose() async {
    setState(() {
      busy = true;
      plan = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (selection == null) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null || bytes.length > 50 * 1024 * 1024)
        throw const FormatException('Arquivo vazio ou maior que 50 MB.');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Entre na sua conta.');
      final validated = validateBackup(utf8.decode(bytes), uid);
      if (!mounted) return;
      setState(() {
        plan = validated;
        message =
            'Backup de ${validated.exportedAt}\n${validated.documents.length} registros da sua conta.\n'
            '${validated.edeskHistory?.length ?? 0} registros de envio ao E-Desk.\n\n'
            'Registros com o mesmo ID serão atualizados. Outros registros serão preservados. '
            'Antes de restaurar, será exportado um backup dos dados atuais.';
      });
    } catch (error) {
      progress('Backup recusado: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    final selected = plan;
    if (selected == null) return;
    setState(() => busy = true);
    try {
      final service = BackupService();
      final current = await service.export(progress: progress);
      if (!await save(current, 'backup_antes_de_restaurar')) {
        progress(
            'Restauração cancelada. Salve o backup dos dados atuais para continuar.');
        return;
      }
      await service.restore(selected, progress: progress);
      if (mounted)
        setState(() {
          plan = null;
          message =
              'Restauração concluída. Recarregue o app para atualizar todas as telas.';
        });
    } catch (error) {
      progress('Não foi possível concluir a restauração: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Backup e restauração'),
        content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Incluídos: projetos ativos e finalizados, horas, comentários, modelos, rascunhos de e-mail salvos na conta, histórico de operações sincronizado e configurações.'),
              const SizedBox(height: 8),
              const Text('Não incluídos: senhas, arquivos originais, anexos de e-mail e cópias locais de recuperação. O histórico de proteção contra reenvios é incluído quando a integração está disponível.'),
              const SizedBox(height: 8),
              Text(lastExport == null ? 'Nenhuma exportação registrada neste dispositivo.' : 'Última exportação gerada: ${DateTime.tryParse(lastExport!)?.toLocal().toString().split('.').first ?? lastExport}. Confira se o arquivo foi salvo.'),
              const SizedBox(height: 16),
              SelectableText(message),
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.download),
                    label: const Text('Exportar backup')),
                OutlinedButton.icon(
                    onPressed: busy ? null : choose,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Selecionar backup')),
              ]),
            ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Fechar')),
          if (plan != null)
            FilledButton(
                onPressed: busy ? null : restore,
                child: const Text('Confirmar restauração'))
        ],
      ));
}
