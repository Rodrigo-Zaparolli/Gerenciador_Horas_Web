import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../data/services/archive_destination_store.dart';
import '../../../data/services/native_local_files_service.dart';

class ArchiveDestinationDialog extends StatefulWidget {
  const ArchiveDestinationDialog({super.key, this.store, this.pickFolder});
  final ArchiveDestinationStore? store;
  final Future<String?> Function()? pickFolder;
  static Future<bool?> show(BuildContext context) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ArchiveDestinationDialog());
  @override
  State<ArchiveDestinationDialog> createState() =>
      _ArchiveDestinationDialogState();
}

class _ArchiveDestinationDialogState extends State<ArchiveDestinationDialog> {
  late final ArchiveDestinationStore store;
  late final String owner;
  final path = TextEditingController();
  String? reference, error;
  String original = '';
  bool busy = false;
  StreamSubscription<User?>? subscription;
  bool get authorized => owner.isNotEmpty && store.currentUserId == owner;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? FirebaseArchiveDestinationStore();
    owner = store.currentUserId ?? '';
    if (widget.store == null)
      subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted && !authorized)
          setState(() {
            path.clear();
            reference = null;
            error = 'A conta mudou. Feche esta janela.';
          });
      });
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      if (!authorized)
        throw StateError('Entre na sua conta para configurar a pasta.');
      final saved = await store.load(owner);
      if (mounted && authorized)
        setState(() {
          path.text =
              saved?.path ?? ArchiveDestination.suggestion(store.currentEmail);
          reference = saved?.reference;
          original = path.text;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick() async {
    if (!authorized || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      String? selected;
      if (widget.pickFolder != null) {
        selected = await widget.pickFolder!();
      } else {
        final result = await NativeLocalFiles.call('pick-folder');
        if (result['cancelled'] != true)
          selected = result['reference'] as String;
      }
      if (!mounted || !authorized || selected == null) return;
      final value =
          ArchiveDestination.fromData({'destination': selected}, owner);
      if (value?.reference == null)
        throw StateError('Selecione uma pasta local válida para esta conta.');
      setState(() {
        path.text = value!.path;
        reference = value.reference;
      });
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!authorized || busy) return;
    final value = ArchiveDestination(path.text.trim(), reference: reference);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      value.toData();
      await store.save(owner, value);
      if (mounted && authorized) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> close() async {
    if (busy) return;
    if (authorized && path.text.trim() != original) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Descartar alteração do destino?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Continuar editando')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Descartar'))
                  ]));
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    subscription?.cancel();
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: AlertDialog(
          title: const Text('Pasta de projetos finalizados'),
          content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (busy) const LinearProgressIndicator(),
                    const Text(
                        'Defina onde os seus projetos finalizados serão guardados. Esta preferência pertence somente à sua conta.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: path,
                        enabled: authorized && !busy,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Caminho da pasta de destino',
                            hintText: r'C:\Clientes\Projetos Finalizados'),
                        onChanged: (_) => setState(() {
                              reference = null;
                              error = null;
                            })),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: authorized && !busy ? pick : null,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Selecionar pasta no Windows')),
                    Text(reference == null
                        ? 'Você pode salvar o caminho digitado. Antes de mover, selecione a pasta no Windows para autorizar o acesso neste computador.'
                        : 'Pasta selecionada neste computador. Clique em Salvar destino para confirmar.'),
                    const SizedBox(height: 12),
                    const Text(
                        'Alterar o destino não move projetos já arquivados. Os próximos movimentos continuarão exigindo conferência. Origem e destino devem estar na mesma unidade/disco.'),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SelectableText(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : close, child: const Text('Cancelar')),
            FilledButton.icon(
                onPressed: authorized && !busy ? save : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar destino')),
          ]));
}
