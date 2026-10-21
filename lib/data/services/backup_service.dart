import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edesk_integration.dart';

const backupCollections = {
  'projects',
  'completed_projects',
  'checklist_formats',
  'work_formats',
  'metrics',
  'orientacoes',
  'configuracoes',
  'metrics_preferences'
  ,'edesk_operations'
};
const backupChildCollections = {
  'time_logs',
  'time_entries',
  'comentarios_edesk',
  'email_drafts'
};

bool _secretKey(String key) =>
    RegExp(r'password|senha|token|credencial|credential|secret',
            caseSensitive: false)
        .hasMatch(key);

bool backupIncludesDocument(String path) => path != 'configuracoes/edesk_credenciais';

dynamic encodeBackupValue(dynamic value) {
  if (value is Timestamp) {
    return {
      '__backupType': 'timestamp',
      'seconds': value.seconds,
      'nanoseconds': value.nanoseconds
    };
  }
  if (value is GeoPoint) {
    return {
      '__backupType': 'geo',
      'latitude': value.latitude,
      'longitude': value.longitude
    };
  }
  if (value is Blob) {
    return {'__backupType': 'blob', 'data': base64Encode(value.bytes)};
  }
  if (value is DocumentReference) {
    return {'__backupType': 'reference', 'path': value.path};
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!_secretKey(entry.key.toString()))
          entry.key.toString(): encodeBackupValue(entry.value)
    };
  }
  if (value is List) return value.map(encodeBackupValue).toList();
  return value;
}

dynamic decodeBackupValue(dynamic value,
    {required String uid, FirebaseFirestore? db}) {
  if (value is List) {
    return value.map((e) => decodeBackupValue(e, uid: uid, db: db)).toList();
  }
  if (value is! Map) return value;
  final type = value['__backupType'];
  if (type == 'timestamp') {
    return Timestamp(value['seconds'] as int, value['nanoseconds'] as int);
  }
  if (type == 'geo') {
    return GeoPoint((value['latitude'] as num).toDouble(),
        (value['longitude'] as num).toDouble());
  }
  if (type == 'blob') return Blob(base64Decode(value['data'] as String));
  if (type == 'reference') {
    final path = value['path'] as String;
    if (!path.startsWith('users/$uid/') || path.split('/').length.isOdd) {
      throw const FormatException('Referência fora da conta do backup.');
    }
    return (db ?? FirebaseFirestore.instance).doc(path);
  }
  if (type != null) {
    throw const FormatException('Tipo de dado de backup desconhecido.');
  }
  return {
    for (final entry in value.entries)
      if (!_secretKey(entry.key.toString()))
        entry.key.toString(): decodeBackupValue(entry.value, uid: uid, db: db)
  };
}

class BackupDocument {
  final String path;
  final Map<String, dynamic> data;
  const BackupDocument(this.path, this.data);
}

class BackupPlan {
  final String uid;
  final List<BackupDocument> documents;
  final Map<String, String>? edeskHistory;
  final String exportedAt;
  const BackupPlan(
      this.uid, this.documents, this.edeskHistory, this.exportedAt);
}

BackupPlan validateBackup(String text, String uid, {FirebaseFirestore? db}) {
  final root = jsonDecode(text);
  if (root is! Map ||
      root['format'] != 'gerenciador_horas_backup' ||
      root['version'] != 1) {
    throw const FormatException(
        'Este arquivo não é um backup compatível do aplicativo.');
  }
  if (root['uid'] != uid) {
    throw const FormatException(
        'Este backup pertence a outra conta. Entre na conta que o exportou.');
  }
  final records = root['documents'];
  if (records is! List || records.length > 100000) {
    throw const FormatException('Lista de documentos inválida.');
  }
  final seen = <String>{};
  final documents = <BackupDocument>[];
  for (final record in records) {
    if (record is! Map || record['path'] is! String || record['data'] is! Map) {
      throw const FormatException('Documento de backup inválido.');
    }
    final path = record['path'] as String;
    final parts = path.split('/');
    final valid = path == 'profile' ||
        (parts.every((e) => e.isNotEmpty && e != '.' && e != '..') &&
            backupCollections.contains(parts.first) &&
            (parts.length == 2 ||
                (parts.length == 4 &&
                    {'projects', 'completed_projects'}.contains(parts.first) &&
                    backupChildCollections.contains(parts[2]))));
    if (!valid || !seen.add(path)) {
      throw const FormatException('Caminho inválido ou repetido no backup.');
    }
    if (!backupIncludesDocument(path)) continue;
    final decoded = Map<String, dynamic>.from(
        decodeBackupValue(record['data'], uid: uid, db: db) as Map);
    documents.add(BackupDocument(path, decoded));
  }
  Map<String, String>? history;
  if (root['edeskHistory'] != null) {
    if (root['edeskHistory'] is! Map) {
      throw const FormatException('Histórico E-Desk inválido.');
    }
    history = Map<String, String>.from(root['edeskHistory']);
    if (history.length > 100000 ||
        history.entries.any((e) =>
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(e.key) ||
            !{'confirmed', 'uncertain', 'pending'}.contains(e.value))) {
      throw const FormatException('Histórico E-Desk inválido.');
    }
    history = history.map((key, value) =>
        MapEntry(key, value == 'pending' ? 'uncertain' : value));
  }
  return BackupPlan(uid, documents, history,
      root['exportedAt']?.toString() ?? 'Data não informada');
}

class BackupService {
  final FirebaseFirestore db;
  final String Function() userIdProvider;
  BackupService(
      {FirebaseFirestore? firestore, String Function()? userIdProvider})
      : db = firestore ?? FirebaseFirestore.instance,
        userIdProvider = userIdProvider ??
            (() =>
                FirebaseAuth.instance.currentUser?.uid ??
                (throw StateError('Entre na sua conta.')));
  String get uid => userIdProvider();

  Future<String> export({void Function(String)? progress}) async {
    final account = uid;
    final user = db.collection('users').doc(account);
    final records = <Map<String, dynamic>>[];
    final profile = await user.get(const GetOptions(source: Source.server));
    if (profile.exists) {
      records
          .add({'path': 'profile', 'data': encodeBackupValue(profile.data())});
    }
    for (final name in backupCollections) {
      progress?.call('Exportando $name…');
      final snapshot = await user
          .collection(name)
          .get(const GetOptions(source: Source.server));
      for (final doc in snapshot.docs) {
        if (!backupIncludesDocument('$name/${doc.id}')) continue;
        records.add(
            {'path': '$name/${doc.id}', 'data': encodeBackupValue(doc.data())});
        if (name == 'projects' || name == 'completed_projects') {
          for (final child in backupChildCollections) {
            final children = await doc.reference
                .collection(child)
                .get(const GetOptions(source: Source.server));
            for (final entry in children.docs) {
              records.add({
                'path': '$name/${doc.id}/$child/${entry.id}',
                'data': encodeBackupValue(entry.data())
              });
            }
          }
        }
      }
    }
    Map<String, dynamic>? history;
    try {
      final result = await EdeskIntegrationApi.call('/api/edesk/history');
      history = Map<String, dynamic>.from(result['items'] as Map);
    } catch (_) {
      /* Firestore backup remains available when local integration is off. */
    }
    if (uid != account) {
      throw StateError('A conta mudou durante o backup. Tente novamente.');
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'gerenciador_horas_backup',
      'version': 1,
      'uid': account,
      'exportedAt': DateTime.now().toIso8601String(),
      'documents': records,
      'edeskHistory': history
    });
  }

  Future<void> restore(BackupPlan plan,
      {void Function(String)? progress}) async {
    final account = uid;
    if (plan.uid != account) {
      throw StateError('Este backup pertence a outra conta.');
    }
    final user = db.collection('users').doc(account);
    await user.get(const GetOptions(source: Source.server));
    if (plan.edeskHistory != null) {
      final health =
          await EdeskIntegrationApi.call('/healthz', authenticated: false);
      if (health['busy'] == true) {
        throw StateError(
            'Aguarde o envio ao E-Desk terminar antes de restaurar.');
      }
      await EdeskIntegrationApi.call('/api/edesk/history',
          body: {'items': plan.edeskHistory!});
    }
    var restored = 0;
    try {
      for (var start = 0; start < plan.documents.length; start += 100) {
        if (uid != account) {
          throw StateError('A conta mudou durante a restauração.');
        }
        final batch = db.batch();
        final chunk = plan.documents.skip(start).take(100);
        for (final record in chunk) {
          final reference = record.path == 'profile'
              ? user
              : db.doc('${user.path}/${record.path}');
          final data = record.path == 'profile'
              ? {
                  for (final key in ['name', 'displayName', 'photoBase64'])
                    if (record.data.containsKey(key)) key: record.data[key],
                }
              : record.data;
          if (data.isNotEmpty) {
            batch.set(reference, data, SetOptions(merge: true));
          }
        }
        await batch.commit();
        restored += chunk.length;
        progress?.call(
            'Restaurados $restored de ${plan.documents.length} registros…');
      }
    } catch (_) {
      throw StateError('A restauração parou após $restored registros. '
          'Verifique a conexão e tente novamente com o mesmo arquivo; os IDs serão preservados.');
    }
  }
}
