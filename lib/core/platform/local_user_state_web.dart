import 'package:web/web.dart' as web;

String? read(String key) => web.window.localStorage.getItem(key);
bool write(String key, String value) {
  web.window.localStorage.setItem(key, value);
  return true;
}

void remove(String key) => web.window.localStorage.removeItem(key);
