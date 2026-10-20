import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/firebase_service.dart';
import '../../../data/services/native_local_files_service.dart';

class ProjectArchiveDialog extends StatefulWidget {
  const ProjectArchiveDialog(
      {super.key,
      required this.projectId,
      required this.folder,
      required this.excel});
  final String projectId, folder, excel;
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
  StreamSubscription<User?>? subscription;
  String? destination, error, message;
  Map<String, dynamic>? plan, moved;
  bool busy = false, confirmed = false;
  bool get authorized =>
      ProjectArchiveDialog.allowed &&
      FirebaseAuth.instance.currentUser?.uid == owner;
  DocumentReference<Map<String, dynamic>> get preferences =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('configuracoes')
          .doc('project_archive');
  @override
  void initState() {
    super.initState();
    owner = FirebaseAuth.instance.currentUser!.uid;
    subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
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
    setState(() => busy = true);
    try {
      final value =
          (await preferences.get().timeout(const Duration(seconds: 15))).data();
      if (mounted && authorized)
        setState(() => destination = value?['destination'] as String?);
    } catch (e) {
      if (mounted && authorized)
        setState(() => error =
            'Selecione a pasta de destino. Não foi possível carregar a preferência: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> selectDestination() async {
    if (busy || !authorized || moved != null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await NativeLocalFiles.call('pick-folder');
      if (!mounted || !authorized || selected['cancelled'] == true) return;
      final reference = selected['reference'] as String;
      setState(() {
        destination = reference;
        plan = null;
        confirmed = false;
      });
      await preferences
          .set({'destination': reference}).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkCompleted() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(owner)
        .collection('completed_projects')
        .doc(widget.projectId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    if (!authorized || !doc.exists || doc.data()?['status'] != 'TRAB_FIM') {
      throw StateError('Esta ação exige um projeto finalizado.');
    }
  }

  Future<void> prepare() async {
    if (busy || !authorized || destination == null) return;
    setState(() {
      busy = true;
      error = null;
      plan = null;
      confirmed = false;
    });
    try {
      await checkCompleted();
      final result = await NativeLocalFiles.call('project-move-prepare',
          reference: widget.folder,
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
      error = null;
    });
    try {
      if (moved == null) {
        if (plan!['alreadyMoved'] != true) await checkCompleted();
        final result = await NativeLocalFiles.call('project-move-commit',
            operation: plan!['operation'] as String);
        if (!mounted || !authorized) return;
        if (result['moved'] != true)
          throw StateError('A movimentação não foi confirmada.');
        moved = result;
      }
      await FirebaseService().applyProjectFolderMove(widget.projectId, moved!);
      if (mounted && authorized) {
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
                    const Text(
                        'A pasta selecionada será movida com suas subpastas. Os vínculos serão atualizados após a conferência. Feche o Excel antes de continuar.'),
                    const SizedBox(height: 12),
                    SelectableText('Pasta atual: ${label(widget.folder)}'),
                    const SizedBox(height: 8),
                    SelectableText(
                        'Pasta de destino: ${destination == null ? "Não selecionada" : label(destination!)}'),
                    OutlinedButton.icon(
                        onPressed: busy || !authorized || moved != null
                            ? null
                            : selectDestination,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Selecionar destino')),
                    const Text(
                        'Nesta versão, o destino deve estar na mesma unidade/disco da pasta atual.'),
                    if (plan != null) ...[
                      const Divider(),
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
                    if (message != null) Text(message!),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Fechar')),
            if (moved == null)
              OutlinedButton(
                  onPressed: busy || !authorized || destination == null
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
