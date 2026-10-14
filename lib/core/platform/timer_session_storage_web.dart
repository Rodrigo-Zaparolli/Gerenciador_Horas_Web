import 'dart:convert';
import 'package:gerenciador_horas/domain/models/timer_session.dart';
import 'package:web/web.dart' as web;

String _key(String userId) => 'gerenciador_horas.timer.$userId';

TimerSession? readTimerSession(String userId) {
  try {
    final value = web.window.sessionStorage.getItem(_key(userId));
    if (value == null) return null;
    final data = jsonDecode(value);
    return data is Map<String, dynamic> ? TimerSession.fromJson(data) : null;
  } catch (_) {
    return null;
  }
}

void writeTimerSession(String userId, TimerSession? session) {
  try {
    if (session == null) {
      web.window.sessionStorage.removeItem(_key(userId));
    } else {
      web.window.sessionStorage
          .setItem(_key(userId), jsonEncode(session.toJson()));
    }
  } catch (_) {
    // Storage can be disabled by the browser; the in-memory timer still works.
  }
}
