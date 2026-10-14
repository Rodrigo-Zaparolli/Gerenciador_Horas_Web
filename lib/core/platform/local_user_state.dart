import 'dart:convert';
import 'local_user_state_stub.dart'
    if (dart.library.js_interop) 'local_user_state_web.dart'
    if (dart.library.io) 'local_user_state_io.dart' as storage;

/// Small recoverable UI state, scoped to account and feature. No credentials.
class LocalUserState {
  /// Test backend; production uses the platform's private local storage.
  static Map<String, String>? memory;
  static String key(String uid, String feature) =>
      'gerenciador_horas.ui.${Uri.encodeComponent(uid)}.${Uri.encodeComponent(feature)}';
  static Map<String, dynamic>? read(String? uid, String feature) {
    if (uid == null || uid.isEmpty) return null;
    try {
      final raw = memory != null
          ? memory![key(uid, feature)]
          : storage.read(key(uid, feature));
      return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static bool write(String? uid, String feature, Map<String, dynamic> data) {
    if (uid == null || uid.isEmpty) return false;
    try {
      final raw = jsonEncode(data);
      if (utf8.encode(raw).length > 2 * 1024 * 1024) return false;
      if (memory != null) {
        memory![key(uid, feature)] = raw;
        return true;
      }
      return storage.write(key(uid, feature), raw);
    } catch (_) {
      return false;
    }
  }

  static void remove(String? uid, String feature) {
    if (uid == null || uid.isEmpty) return;
    try {
      if (memory != null) {
        memory!.remove(key(uid, feature));
      } else {
        storage.remove(key(uid, feature));
      }
    } catch (_) {}
  }
}
