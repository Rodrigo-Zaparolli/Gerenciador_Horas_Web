import 'package:web/web.dart' as web;

bool prefersLocalAuthStorage() {
  try {
    return web.window.localStorage.getItem('gerenciador_horas.auth.storage') ==
        'local';
  } catch (_) {
    return false;
  }
}
