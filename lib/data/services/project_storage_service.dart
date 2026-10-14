import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProjectStorageFile {
  final String name;
  final String reference;
  final int? size;

  const ProjectStorageFile({
    required this.name,
    required this.reference,
    this.size,
  });
}

class ProjectStorageService {
  ProjectStorageService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const String referencePrefix = 'firebase-storage://';
  static const int maxFileSizeBytes = 25 * 1024 * 1024;

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  String projectFolderReference(String projectId) {
    final userId = _requireUserId();
    final safeProjectId = _safePathComponent(projectId);
    return _toReference('users/$userId/projects/$safeProjectId/files/');
  }

  static bool isStorageReference(String? value) =>
      value?.startsWith(referencePrefix) ?? false;

  static String fileNameFromReference(String reference) {
    final path = reference.startsWith(referencePrefix)
        ? reference.substring(referencePrefix.length)
        : reference;
    return path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? path;
  }

  Future<String> uploadProjectFile({
    required String folderReference,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes.length, 'bytes', 'O arquivo está vazio.');
    }
    if (bytes.length > maxFileSizeBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'O arquivo excede o limite de 25 MB.',
      );
    }

    final folderPath = _validatedPath(folderReference);
    if (!folderPath.endsWith('/files/')) {
      throw ArgumentError.value(
        folderReference,
        'folderReference',
        'Referência de pasta de projeto inválida.',
      );
    }

    final safeFileName = _safeFileName(fileName);
    final uniqueFileName =
        '${DateTime.now().microsecondsSinceEpoch}_$safeFileName';
    final reference = _toReference('$folderPath$uniqueFileName');
    final storageReference = _storage.ref().child('$folderPath$uniqueFileName');

    await storageReference.putData(
      bytes,
      SettableMetadata(contentType: _contentType(safeFileName)),
    );

    return reference;
  }

  Future<List<ProjectStorageFile>> listFiles(String folderReference) async {
    final folderPath = _validatedPath(folderReference);
    if (!folderPath.endsWith('/files/')) {
      throw ArgumentError.value(
        folderReference,
        'folderReference',
        'Referência de pasta de projeto inválida.',
      );
    }

    final result = await _storage.ref().child(folderPath).listAll();
    final files = await Future.wait(
      result.items.map((item) async {
        final metadata = await item.getMetadata();
        return ProjectStorageFile(
          name: item.name,
          reference: _toReference(item.fullPath),
          size: metadata.size,
        );
      }),
    );
    files.sort((left, right) => left.name.compareTo(right.name));
    return files;
  }

  Future<Uint8List> downloadBytes(String fileReference) async {
    final path = _validatedPath(fileReference);
    final bytes = await _storage.ref().child(path).getData(maxFileSizeBytes);
    if (bytes == null) {
      throw StateError('O Firebase Storage não retornou o conteúdo do arquivo.');
    }
    return bytes;
  }

  Future<String> downloadUrl(String fileReference) async {
    final path = _validatedPath(fileReference);
    return _storage.ref().child(path).getDownloadURL();
  }

  Future<void> deleteFile(String fileReference) async {
    final path = _validatedPath(fileReference);
    await _storage.ref().child(path).delete();
  }

  String _requireUserId() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('É necessário entrar para acessar arquivos do projeto.');
    }
    return user.uid;
  }

  String _validatedPath(String reference) {
    if (!reference.startsWith(referencePrefix)) {
      throw ArgumentError.value(
        reference,
        'reference',
        'Referência do Firebase Storage inválida.',
      );
    }

    final path = reference.substring(referencePrefix.length);
    final expectedPrefix = 'users/${_requireUserId()}/projects/';
    if (!path.startsWith(expectedPrefix) || path.contains('..')) {
      throw ArgumentError.value(
        reference,
        'reference',
        'A referência não pertence ao usuário autenticado.',
      );
    }
    return path;
  }

  String _toReference(String path) => '$referencePrefix$path';

  String _safePathComponent(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    if (safe.isEmpty) {
      throw ArgumentError.value(value, 'projectId', 'ID do projeto inválido.');
    }
    return safe;
  }

  String _safeFileName(String value) {
    final name = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..') {
      throw ArgumentError.value(value, 'fileName', 'Nome de arquivo inválido.');
    }
    return name;
  }

  String _contentType(String fileName) {
    switch (fileName.split('.').last.toLowerCase()) {
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xlsm':
        return 'application/vnd.ms-excel.sheet.macroEnabled.12';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'pdf':
        return 'application/pdf';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      default:
        throw ArgumentError.value(
          fileName,
          'fileName',
          'Este tipo de arquivo não é permitido.',
        );
    }
  }
}

extension on Iterable<String> {
  String? get lastOrNull {
    if (isEmpty) {
      return null;
    }
    return last;
  }
}
