import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:gerenciador_horas/core/config/web_config.dart';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/project_storage_service.dart';
import 'package:gerenciador_horas/data/services/file_download.dart';
import 'package:url_launcher/url_launcher.dart';
import 'native_local_files_service.dart';
import 'browser_local_files_service.dart';

class ProjectFileService {
  static bool isWebLink(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Keeps legacy paths only while their field remains unchanged.
  static String? editedReference(String value, String? previous) {
    final field = value.trim();
    if (field.isEmpty) return null;
    if (!kIsWeb || field == previous || isWebLink(field)) return field;
    if (BrowserLocalFiles.isReference(field)) return field;
    if (ProjectStorageService.isStorageReference(field) &&
        WebConfig.storageEnabled) {
      return field;
    }
    throw ArgumentError(
        'Informe um link HTTP/HTTPS válido ou selecione um anexo.');
  }

  static String cloudFolder(String projectId) {
    if (!WebConfig.storageEnabled) {
      throw StateError(
          'Use um link de pasta compartilhada. O armazenamento de anexos não está configurado.');
    }
    if (projectId.trim().isEmpty) {
      throw ArgumentError('Informe o ID do projeto.');
    }
    return ProjectStorageService().projectFolderReference(projectId.trim());
  }

  static Future<String?> pickFile(String projectId) async {
    if (kIsWeb && !WebConfig.storageEnabled) {
      return BrowserLocalFiles.pickFile();
    }
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
        'txt'
      ],
      withData: kIsWeb,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (!kIsWeb) return file.path;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('Não foi possível ler o arquivo selecionado.');
    }
    return ProjectStorageService().uploadProjectFile(
      folderReference: cloudFolder(projectId),
      fileName: file.name,
      bytes: bytes,
    );
  }

  static Future<void> openFile(String reference) async {
    var value = reference.trim();
    if (BrowserLocalFiles.isReference(value)) {
      if (!kIsWeb) {
        throw StateError(
            'Este vínculo pertence a um navegador. Selecione o arquivo ou pasta neste computador.');
      }
      await NativeLocalFiles.call('open', reference: value);
      return;
    }
    if (ProjectStorageService.isStorageReference(value)) {
      if (kIsWeb && !WebConfig.storageEnabled) {
        throw StateError('O armazenamento de anexos não está configurado.');
      }
      if (kIsWeb) {
        final bytes = await ProjectStorageService().downloadBytes(value);
        downloadBytes(
          fileName: ProjectStorageService.fileNameFromReference(value),
          bytes: bytes,
          mimeType: 'application/octet-stream',
        );
        return;
      }
      value = await ProjectStorageService().downloadUrl(value);
    }
    if (kIsWeb && !isWebLink(value)) {
      await NativeLocalFiles.call('open', reference: value);
      return;
    }
    final uri = isWebLink(value) ? Uri.parse(value) : await localPathUri(value);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Não foi possível abrir o arquivo ou link.');
    }
  }
}
