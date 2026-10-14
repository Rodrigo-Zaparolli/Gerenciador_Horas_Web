import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}appearance.txt');

Future<String?> readThemePreference() async {
  try {
    final file = await _file();
    return await file.exists() ? (await file.readAsString()).trim() : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeThemePreference(String value) async {
  try {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  } catch (_) {
    // Appearance storage never blocks an application action.
  }
}
