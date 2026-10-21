import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/archive_destination_store.dart';
import 'archive_destination_dialog.dart';
import 'project_archive_service.dart';

class ProjectArchiveDialog extends StatefulWidget {
  const ProjectArchiveDialog(
      {super.key,
      required this.projectId,
      required this.folder,
      required this.excel,
      this.service});
  final String projectId, folder, excel;
  final ProjectArchiveService? service;
  static bool acceptsFolder(String folder) =>
      folder.startsWith('desktop-folder:') ||
      folder.startsWith('browser-folder:') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(folder) ||
      folder.startsWith(r'\\');
  static bool get allowed {
    final user = FirebaseAuth.instance.currentUser;
    return PilotFeatureAccess.allows(uid: user?.uid, email: user?.email);
  }

  static Future<Map<String, dynamic>?> show(BuildContext context,
      {required String projectId,
      required String folder,
      required String excel}) {
    if (!allowed || !acceptsFolder(folder)) return Future.value(null);
    return showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProjectArchiveDialog(
            projectId: projectId, folder: folder, excel: excel));
  }

  @override
  State<ProjectArchiveDialog> createState() => _ProjectArchiveDialogState();
}

class _ProjectArchiveDialogState extends State<ProjectArchiveDialog> {
  late final String owner;
  late final ProjectArchiveService service;
  StreamSubscription<void>? subscription;
  String? destination, sourceReference, error, message;
  String activity = '';
  Map<String, dynamic>? plan, moved;
  bool busy = false, confirmed = false;
  bool get authorized => service.allowed && service.uid == owner;
  bool get needsProjectRoot =>
      sourceReference == null &&
      label(widget.folder).split(RegExp(r'[\\/]')).last.toLowerCase() ==
          'documentos';
  @override
  void initState() {
    super.initState();
    service = widget.service ?? ProjectArchiveService();
    owner = service.uid!;
    subscription = service.accountChanges.listen((_) {
      if (mounted && !authorized)
        setState(() {
          plan = null;
          moved = null;
          destination = null;
          error = 'A conta mudou. Feche esta janela.';
        });
    });
    loadDestination();
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> loadDestination() async {
    setState(() {
      busy = true;
      activity = 'Carregando destino…';
      error = null;
      plan = null;
      confirmed = false;
    });
    try {
      final value = await service.loadDestination(owner);
      if (mounted && authorized)
        setState(() {
          final suggestion = ArchiveDestination.suggestion(service.email);
          destination =
              value?.destination ?? (suggestion.isEmpty ? null : suggestion);
        });
    } catch (e) {
      if (mounted && authorized)
        setState(() => error =
            'Selecione a pasta de destino. Não foi possível carregar a preferência: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized && destination != null && error == null)
      await prepare();
  }

  Future<void> selectDestination() async {
    if (busy || !authorized || moved != null) return;
    setState(() {
      busy = true;
      activity = 'Selecione a pasta de destino na janela do Windows.';
      error = null;
    });
    try {
      final selected = await service.call('pick-folder');
      if (!mounted || !authorized || selected['cancelled'] == true) return;
      final reference = selected['reference'] as String;
      setState(() {
        destination = reference;
        plan = null;
        confirmed = false;
      });
      final value =
          ArchiveDestination.fromData({'destination': reference}, owner);
      if (value == null) throw StateError('Destino inválido.');
      await service.saveDestination(owner, value);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized && error == null) await prepare();
  }

  Future<void> checkCompleted() async {
    await service.checkCompleted(owner, widget.projectId);
    if (!authorized) throw StateError('A conta mudou. Feche esta janela.');
  }

  Future<void> selectProjectRoot() async {
    if (busy || !authorized || moved != null) return;
    setState(() {
      busy = true;
      error = null;
      activity = 'Selecione a pasta principal do projeto na janela do Windows.';
    });
    try {
      final selected = await service.call('pick-folder');
      if (!mounted || !authorized || selected['cancelled'] == true) return;
      setState(() {
        sourceReference = selected['reference'] as String;
        plan = null;
        confirmed = false;
      });
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized && error == null) await prepare();
  }

  Future<void> authorizeLinks() async {
    if (busy || !authorized || moved != null || destination == null) return;
    setState(() {
      busy = true;
      activity = 'Autorize os caminhos solicitados na janela do Windows.';
      error = null;
      plan = null;
      confirmed = false;
      message = null;
    });
    try {
      for (final reference in [
        widget.folder,
        widget.excel,
        if (sourceReference != null) sourceReference!,
        destination!
      ]) {
        if (reference.isEmpty) continue;
        final result = await service.call('authorize', reference: reference);
        if (!mounted || !authorized) return;
        if (result['cancelled'] == true) {
          setState(
              () => message = 'Seleção cancelada. A pasta não foi movida.');
          return;
        }
      }
      if (mounted && authorized) {
        setState(() =>
            message = 'Vínculos autorizados. Clique em Conferir movimentação.');
      }
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized && error == null) await prepare();
  }

  Future<void> prepare() async {
    if (busy || !authorized || destination == null || needsProjectRoot) return;
    setState(() {
      busy = true;
      activity = 'Conferindo pasta, planilha e destino…';
      error = null;
      message = null;
      plan = null;
      confirmed = false;
    });
    try {
      await checkCompleted();
      final result = await service.call('project-move-prepare',
          reference: widget.folder,
          sourceReference: sourceReference,
          destination: destination,
          excelReference: widget.excel);
      if (mounted && authorized) setState(() => plan = result);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> move() async {
    if (busy || !authorized || plan == null || !confirmed && moved == null)
      return;
    setState(() {
      busy = true;
      activity = moved == null
          ? 'Movendo a pasta e atualizando os vínculos…'
          : 'Atualizando os vínculos…';
      error = null;
    });
    try {
      if (moved == null) {
        if (plan!['alreadyMoved'] != true) await checkCompleted();
        final result = await service.call('project-move-commit',
            operation: plan!['operation'] as String);
        if (!mounted || !authorized) return;
        if (result['moved'] != true)
          throw StateError('A movimentação não foi confirmada.');
        moved = result;
      }
      if (!authorized) throw StateError('A conta mudou.');
      await service.applyMove(widget.projectId, moved!);
      if (mounted && authorized) {
        final cleanup = moved!['backupCleanup'];
        if (cleanup is Map && cleanup['complete'] == false) {
          setState(() => busy = false);
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Pasta movida; limpeza de backups pendente'),
              content: SingleChildScrollView(
                child: SelectableText(
                  'Os vínculos foram atualizados. Alguns backups não puderam ser excluídos. '
                  'Confira a pasta .gerenciador-backups no destino.\n\n'
                  '${(cleanup['warnings'] as List? ?? []).join('\n')}',
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendi'))
              ],
            ),
          );
          if (!mounted || !authorized) return;
        }
        setState(() => message = 'Pasta movida e vínculos atualizados.');
        Navigator.pop(context, moved);
      }
    } catch (e) {
      if (mounted && authorized)
        setState(() => error = moved == null
            ? e.toString()
            : 'A pasta já foi movida. Falta atualizar os vínculos no sistema. Clique em Atualizar vínculos; a pasta não será movida novamente. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String label(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme.startsWith('desktop-')
        ? uri.pathSegments.last
        : value;
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: const Text('Mover pasta do projeto finalizado'),
          content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (busy) const LinearProgressIndicator(),
                    if (busy) Text(activity),
                    const Text(
                        'A pasta selecionada será movida com suas subpastas. Os vínculos serão atualizados após a conferência e os backups automáticos serão excluídos após a movimentação confirmada. Feche o Excel antes de continuar.'),
                    const SizedBox(height: 12),
                    SelectableText('Pasta atual: ${label(widget.folder)}'),
                    if (widget.excel.isNotEmpty)
                      SelectableText(
                          'Planilha vinculada: ${label(widget.excel)}'),
                    if (needsProjectRoot)
                      const Text(
                          'O vínculo aponta para Documentos. Selecione a pasta principal do projeto para mover todo o conteúdo.'),
                    if (sourceReference != null)
                      SelectableText(
                          'Pasta inteira a mover: ${label(sourceReference!)}'),
                    TextButton.icon(
                        onPressed: busy || !authorized || moved != null
                            ? null
                            : selectProjectRoot,
                        icon: const Icon(Icons.drive_file_move_outline),
                        label:
                            const Text('Selecionar pasta inteira do projeto')),
                    const SizedBox(height: 8),
                    SelectableText(
                        'Pasta de destino: ${destination == null ? "Não selecionada" : label(destination!)}'),
                    OutlinedButton.icon(
                        onPressed: busy || !authorized || moved != null
                            ? null
                            : selectDestination,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Selecionar destino')),
                    TextButton.icon(
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Configurar meu destino padrão'),
                        onPressed: busy || !authorized || moved != null
                            ? null
                            : () async {
                                final saved =
                                    await ArchiveDestinationDialog.show(
                                        context);
                                if (mounted && authorized && saved == true) {
                                  setState(() {
                                    plan = null;
                                    confirmed = false;
                                  });
                                  await loadDestination();
                                }
                              }),
                    const Text(
                        'Nesta versão, o destino deve estar na mesma unidade/disco da pasta atual.'),
                    if (plan != null) ...[
                      const Divider(),
                      const Text(
                          'Confira os caminhos abaixo e marque a confirmação para liberar o botão.'),
                      SelectableText(
                          'De: ${plan!['source']}\nPara: ${plan!['target']}'),
                      if (widget.excel.isNotEmpty)
                        Text(plan!['excelInside'] == true
                            ? 'A planilha está dentro da pasta e terá seu vínculo atualizado.'
                            : 'A planilha está fora da pasta e permanecerá no local atual.'),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: confirmed,
                          title: Text(plan!['alreadyMoved'] == true
                              ? 'Conferi os caminhos e quero recuperar os vínculos.'
                              : 'Conferi os caminhos e confirmo a movimentação.'),
                          onChanged: busy || !authorized
                              ? null
                              : (value) =>
                                  setState(() => confirmed = value == true)),
                    ],
                    if (error != null)
                      SelectableText(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (error != null && moved == null)
                      TextButton.icon(
                          onPressed: busy || !authorized || destination == null
                              ? null
                              : authorizeLinks,
                          icon: const Icon(Icons.folder_copy_outlined),
                          label: const Text('Autorizar vínculos neste PC')),
                    if (message != null) Text(message!),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Fechar')),
            if (moved == null)
              OutlinedButton(
                  onPressed: busy ||
                          !authorized ||
                          destination == null ||
                          needsProjectRoot
                      ? null
                      : prepare,
                  child: const Text('Conferir movimentação')),
            FilledButton(
                onPressed: busy ||
                        !authorized ||
                        plan == null ||
                        !confirmed && moved == null
                    ? null
                    : move,
                child: Text(moved == null
                    ? 'Confirmar e mover'
                    : 'Atualizar vínculos')),
          ]));
}
