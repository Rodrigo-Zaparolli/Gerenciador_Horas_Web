import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/pilot_feature_access.dart';

abstract class SpreadsheetStore {
  Future<Map<String, dynamic>?> load(
      String uid, String project, String reference);
  Future<void> save(
      String uid, String project, String reference, Map<String, dynamic> data);
}

class FirebaseSpreadsheetStore implements SpreadsheetStore {
  void check(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != uid ||
        !PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      throw StateError('A conta mudou.');
    }
  }

  DocumentReference<Map<String, dynamic>> document(
          String uid, String project) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('projects')
          .doc(project)
          .collection('spreadsheet')
          .doc('snapshot');

  @override
  Future<Map<String, dynamic>?> load(
      String uid, String project, String reference) async {
    check(uid);
    final value = (await document(uid, project)
            .get()
            .timeout(const Duration(seconds: 15)))
        .data();
    check(uid);
    if (value == null ||
        value['reference'] != reference ||
        value['schema'] != 1) {
      return null;
    }
    final data =
        Map<String, dynamic>.from(jsonDecode(value['payload'] as String));
    return {...data, 'syncedAt': value['syncedAt']};
  }

  @override
  Future<void> save(String uid, String project, String reference,
      Map<String, dynamic> data) async {
    check(uid);
    final payload = jsonEncode(data);
    if (utf8.encode(payload).length > 850000) {
      throw StateError(
          'Os dados excedem o limite de armazenamento da planilha.');
    }
    await document(uid, project).set({
      'schema': 1,
      'reference': reference,
      'payload': payload,
      'syncedAt': DateTime.now().toIso8601String()
    }).timeout(const Duration(seconds: 15));
    check(uid);
  }
}
