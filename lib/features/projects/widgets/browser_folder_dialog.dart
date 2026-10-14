import 'package:flutter/material.dart';
import '../../../data/services/browser_local_files_service.dart';

class BrowserFolderDialog extends StatefulWidget {
  const BrowserFolderDialog({super.key, required this.reference});
  final String reference;
  @override
  State<BrowserFolderDialog> createState() => _BrowserFolderDialogState();
}

class _BrowserFolderDialogState extends State<BrowserFolderDialog> {
  List<String> path = [];
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await BrowserLocalFiles.call('list',
          reference: widget.reference, path: path);
      if (!mounted) return;
      items = (result['items'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (failure) {
      if (mounted) error = failure.toString().replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> download(String name) async {
    try {
      await BrowserLocalFiles.call('download',
          reference: widget.reference, path: path, name: name);
    } catch (failure) {
      if (mounted)
        setState(
            () => error = failure.toString().replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(BrowserLocalFiles.label(widget.reference)),
        content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height * .55,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Pasta deste navegador. Os arquivos ficam no computador e não são enviados à nuvem.'),
              if (path.isNotEmpty)
                TextButton.icon(
                    onPressed: loading
                        ? null
                        : () {
                            path.removeLast();
                            load();
                          },
                    icon: const Icon(Icons.arrow_back),
                    label: Text(path.join(' / '))),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!)),
              Expanded(
                  child: !loading && error == null && items.isEmpty
                      ? const Center(child: Text('Esta pasta está vazia.'))
                      : ListView.builder(
                          itemCount: error == null ? items.length : 0,
                          itemBuilder: (context, index) {
                            final item = items[index],
                                directory = item['kind'] == 'directory';
                            return ListTile(
                                leading: Icon(directory
                                    ? Icons.folder
                                    : Icons.insert_drive_file),
                                title: Text(item['name'] as String),
                                trailing: Icon(directory
                                    ? Icons.chevron_right
                                    : Icons.download),
                                enabled: !loading,
                                onTap: () {
                                  if (directory) {
                                    path.add(item['name'] as String);
                                    load();
                                  } else {
                                    download(item['name'] as String);
                                  }
                                });
                          })),
            ])),
        actions: [
          TextButton(
              onPressed: loading ? null : load,
              child: const Text('Atualizar / permitir acesso')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'))
        ],
      );
}
