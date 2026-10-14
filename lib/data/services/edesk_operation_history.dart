import '../../core/platform/local_user_state.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Presentation history only; never replaces the E-Desk confirmation ledger.
class EdeskOperationHistory {
  static const outboxFeature = 'edesk.operations.outbox';
  static final _flushing = <String>{};
  static Future<void> flush(
    String? uid, {
    Future<void> Function(Map<String, dynamic>)? writer,
    bool Function()? isCurrentAccount,
  }) async {
    if (uid == null || !_flushing.add(uid)) return;
    bool current() =>
        isCurrentAccount?.call() ??
        (LocalUserState.memory == null &&
            FirebaseAuth.instance.currentUser?.uid == uid);
    try {
      if (!current()) return;
      final queued =
          LocalUserState.read(uid, outboxFeature)?['items'] as List? ?? [];
      for (final raw in queued) {
        if (!current()) break;
        final item = Map<String, dynamic>.from(raw as Map);
        final id = item['id']?.toString() ?? '';
        if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) continue;
        try {
          if (writer != null) {
            await writer(item);
          } else {
            final database = FirebaseFirestore.instance;
            final ref = database
                .collection('users')
                .doc(uid)
                .collection('edesk_operations')
                .doc(id);
            await database.runTransaction((transaction) async {
              final remote = (await transaction.get(ref)).data();
              if (!shouldReplace(remote, item)) return;
              transaction.set(ref, item);
            }).timeout(const Duration(seconds: 8));
          }
          if (!current()) break;
          final latest =
              LocalUserState.read(uid, outboxFeature)?['items'] as List? ?? [];
          latest.removeWhere((row) =>
              row['id'] == id &&
              row['state'] == item['state'] &&
              row['updated'] == item['updated']);
          LocalUserState.write(uid, outboxFeature, {'items': latest});
        } catch (_) {
          break;
        }
      }
    } catch (_) {
      /* Corrupt cache cannot interrupt the application. */
    } finally {
      _flushing.remove(uid);
    }
  }

  static void _queue(String uid, Map<String, dynamic> item) {
    final rows =
        LocalUserState.read(uid, outboxFeature)?['items'] as List? ?? [];
    rows.removeWhere((row) => row['id'] == item['id']);
    rows.add(Map<String, dynamic>.from(item));
    LocalUserState.write(uid, outboxFeature, {'items': rows});
    unawaited(flush(uid));
  }

  static const feature = 'edesk.operations';

  /// A delayed write cannot erase a confirmation or a newer result.
  static bool shouldReplace(
      Map<String, dynamic>? remote, Map<String, dynamic> item) {
    if (remote?['state'] == 'confirmed' && item['state'] != 'confirmed')
      return false;
    final remoteTime = DateTime.tryParse(
        (remote?['updated'] ?? remote?['created'] ?? '').toString());
    final localTime = DateTime.tryParse(
        (item['updated'] ?? item['created'] ?? '').toString());
    return !(remoteTime != null &&
        localTime != null &&
        (item['state'] != 'confirmed' || remote?['state'] == 'confirmed') &&
        remoteTime.isAfter(localTime));
  }

  static int pendingSync(String? uid) {
    try {
      return (LocalUserState.read(uid, outboxFeature)?['items'] as List? ?? [])
          .length;
    } catch (_) {
      return 0;
    }
  }

  static final _session = <String, Map<String, dynamic>>{};
  static void clearSession() => _session.clear();
  static List<Map<String, dynamic>> read(String? uid) {
    if (uid == null) return [];
    List<Map<String, dynamic>> stored = [];
    try {
      stored = (LocalUserState.read(uid, feature)?['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {/* A damaged local cache must not interrupt a delivery. */}
    return combine(
        stored,
        _session.entries
            .where((e) => e.key.startsWith('$uid/'))
            .map((e) => e.value));
  }

  static List<Map<String, dynamic>> combine(
      Iterable<Map<String, dynamic>> first,
      Iterable<Map<String, dynamic>> second) {
    final merged = <Object?, Map<String, dynamic>>{};
    for (final row in [...first, ...second]) {
      if (merged[row['id']]?['state'] == 'confirmed' &&
          row['state'] != 'confirmed') continue;
      merged[row['id']] = row;
    }
    final rows = merged.values.toList()
      ..sort((a, b) => (b['created']?.toString() ?? '')
          .compareTo(a['created']?.toString() ?? ''));
    return rows.take(200).toList();
  }

  static String? begin(String? uid, String path, Map<String, dynamic>? body) {
    if (uid == null ||
        !['horas', 'comentarios', 'fases'].contains(path.split('/').last))
      return null;
    final request = body?['request'] as Map? ?? {};
    final works = (request['trabalhos'] as List? ?? []).whereType<Map>();
    final projects = works
        .map((work) => work['solicitacao']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final id = body?['operationId']?.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final items = read(uid);
    items.removeWhere((e) => e['id'] == id);
    items.insert(0, {
      'id': id,
      'action': path.split('/').last,
      'project': projects.isNotEmpty
          ? projects.join(', ')
          : (request['solicitacao'] ?? request['id'] ?? '').toString(),
      'entries': works.fold<int>(
          0, (total, work) => total + (work['horas'] as List? ?? []).length),
      'created': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'sending': body?['enviar'] == true,
    });
    _session['$uid/$id'] = items.first;
    if (_session.length > 500) _session.remove(_session.keys.first);
    LocalUserState.write(uid, feature, {'items': items.take(200).toList()});
    _queue(uid, items.first);
    return id;
  }

  static void update(String? uid, String? id, String state) {
    if (id == null) return;
    final items = read(uid);
    for (final item in items.where((e) => e['id'] == id)) {
      // Late polling or a lost response must never downgrade a confirmation.
      if (item['state'] == 'confirmed') return;
      item['state'] = state;
      item['updated'] = DateTime.now().toUtc().toIso8601String();
      _session['$uid/$id'] = item;
    }
    LocalUserState.write(uid, feature, {'items': items});
    for (final item in items.where((item) => item['id'] == id)) {
      if (uid != null) _queue(uid, item);
    }
  }

  static Future<List<Map<String, dynamic>>> loadAccount(String uid) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return [];
    final result = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('edesk_operations')
        .orderBy('created', descending: true)
        .limit(200)
        .get()
        .timeout(const Duration(seconds: 12));
    if (FirebaseAuth.instance.currentUser?.uid != uid) return [];
    return result.docs.map((doc) => doc.data()).toList();
  }

  static String label(String state) => switch (state) {
        'confirmed' => 'Confirmado',
        'tested' => 'Teste concluído',
        'failed' => 'Não confirmado',
        'uncertain' => 'Conferir no E-Desk',
        _ => 'Pendente / conferir no E-Desk',
      };
}
