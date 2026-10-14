import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<String> readLocalText(String path) =>
    File(path).readAsString(encoding: utf8);
Future<void> writeLocalBytes(String path, Uint8List bytes) =>
    File(path).writeAsBytes(bytes).then((_) {});

Future<String> createLocalFolder(String base, String name) async {
  final directory = Directory(
    '${base.replaceAll(RegExp(r'[\\/]+$'), '')}${Platform.pathSeparator}$name',
  );
  await directory.create(recursive: true);
  return directory.path;
}

Future<Uri> localPathUri(String path) async {
  final file = File(path);
  if (await file.exists()) return Uri.file(file.path);
  final directory = Directory(path);
  if (await directory.exists()) return Uri.directory(directory.path);
  throw StateError('O arquivo ou pasta não foi encontrado.');
}
