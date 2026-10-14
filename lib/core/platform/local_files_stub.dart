import 'dart:typed_data';

Never _unavailable() => throw UnsupportedError(
      'O navegador não acessa caminhos locais. Selecione um arquivo ou use um link compartilhado.',
    );

Future<String> readLocalText(String path) async => _unavailable();
Future<void> writeLocalBytes(String path, Uint8List bytes) async =>
    _unavailable();
Future<String> createLocalFolder(String base, String name) async =>
    _unavailable();
Future<Uri> localPathUri(String path) async => _unavailable();
