import 'package:web/web.dart' as web;

bool keepLoginPreference() {
  try {
    return web.window.localStorage
            .getItem('gerenciador_horas.auth.keepConnected') !=
        'false';
  } catch (_) {
    return true;
  }
}

void rememberLoginPreference(bool keep) {
  try {
    web.window.localStorage
        .setItem('gerenciador_horas.auth.keepConnected', '$keep');
  } catch (_) {/* This preference never replaces Firebase persistence. */}
}

bool prefersLocalAuthStorage() {
  try {
    return web.window.localStorage.getItem('gerenciador_horas.auth.storage') ==
        'local';
  } catch (_) {
    return false;
  }
}

/// Check the durable store before signing in, and remember the backend so
/// Firebase restores from that same store before the login screen is built.
bool prepareLocalAuthStorage() {
  const key = 'gerenciador_horas.auth.storage';
  try {
    web.window.localStorage.setItem(key, 'local');
    return web.window.localStorage.getItem(key) == 'local';
  } catch (_) {
    return false;
  }
}
