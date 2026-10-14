import 'dart:io';

File _file(String key) {
  final base =
      Platform.environment['LOCALAPPDATA'] ?? Platform.environment['HOME'];
  if (base == null) throw StateError('Local storage unavailable');
  final directory = Directory('$base/gerenciador_horas/ui_state');
  directory.createSync(recursive: true);
  return File('${directory.path}/${Uri.encodeComponent(key)}.json');
}

String? read(String key) {
  final file = _file(key);
  return file.existsSync() ? file.readAsStringSync() : null;
}

bool write(String key, String value) {
  _file(key).writeAsStringSync(value, flush: true);
  return true;
}

void remove(String key) {
  final file = _file(key);
  if (file.existsSync()) file.deleteSync();
}
