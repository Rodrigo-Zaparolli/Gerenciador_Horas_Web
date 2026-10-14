import 'package:web/web.dart' as web;

const _key = 'gerenciador_horas.appearance';
Future<String?> readThemePreference() async {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

Future<void> writeThemePreference(String value) async {
  try {
    web.window.localStorage.setItem(_key, value);
  } catch (_) {
    // The switch remains usable when browser storage is unavailable.
  }
}
