import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/data/services/project_storage_service.dart';
import 'package:gerenciador_horas/data/services/project_file_service.dart';

Future<void> showProjectStorageFilesDialog(
  BuildContext context, {
  required String folderReference,
}) async {
  final storageService = ProjectStorageService();
  Future<List<ProjectStorageFile>> filesFuture =
      storageService.listFiles(folderReference);
  bool uploading = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Arquivos do projeto'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: FutureBuilder<List<ProjectStorageFile>>(
            future: filesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                      'Não foi possível carregar os arquivos: ${snapshot.error}'),
                );
              }

              final files = snapshot.data!;
              if (files.isEmpty) {
                return const Center(
                  child: Text('Ainda não há arquivos nesta pasta.'),
                );
              }

              return ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final size = file.size == null
                      ? ''
                      : ' · ${(file.size! / 1024).toStringAsFixed(0)} KB';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(file.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(size),
                    trailing: IconButton(
                      tooltip: 'Abrir ou baixar arquivo',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () async {
                        try {
                          await ProjectFileService.openFile(file.reference);
                        } catch (error) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Erro ao abrir o arquivo: $error'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              if (uploading) return;
              setDialogState(() => uploading = true);
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'xlsx',
                    'xls',
                    'xlsm',
                    'csv',
                    'doc',
                    'docx',
                    'pdf',
                    'txt',
                  ],
                  withData: true,
                );
                if (result == null) {
                  return;
                }

                final file = result.files.single;
                final bytes = file.bytes;
                if (bytes == null) {
                  throw StateError(
                      'O navegador não disponibilizou o conteúdo do arquivo.');
                }

                await storageService.uploadProjectFile(
                  folderReference: folderReference,
                  fileName: file.name,
                  bytes: bytes,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  filesFuture = storageService.listFiles(folderReference);
                });
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao enviar o arquivo: $error'),
                    ),
                  );
                }
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => uploading = false);
                }
              }
            },
            icon: const Icon(Icons.upload_file),
            label: Text(uploading ? 'Enviando...' : 'Enviar arquivo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    ),
  );
}
