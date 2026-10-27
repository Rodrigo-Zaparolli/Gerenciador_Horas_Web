import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String? defaultProjectWorksheet(String serviceType) {
  final type = serviceType.toLowerCase().replaceAll(RegExp(r'[áàâãä]'), 'a');
  if (type.contains('consultoria') &&
      !type.contains('catalog') &&
      !type.contains('plugin')) {
    return 'Consultorias';
  }
  return type.contains('treinamento') && type.contains('catalog')
      ? 'Cronogramas'
      : null;
}

int? mappedWorksheetTab(String? name) {
  final value = (name ?? '').trim().toLowerCase();
  if (value.contains('entrada')) return 0;
  if (value == 'checklist-processo' ||
      value == 'maker checklist-processo' ||
      value == 'professional checklist-processo') {
    return 1;
  }
  if (value.contains('linha do tempo')) return 2;
  return null;
}

class ProjectWorksheetPreference {
  static void check(String uid) {
    if (uid.trim().isEmpty || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('A conta mudou.');
    }
  }

  static DocumentReference<Map<String, dynamic>> document(
          String uid, String project) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('projects')
          .doc(project)
          .collection('spreadsheet')
          .doc('view-settings');
  static Future<String?> load(String uid, String project) async {
    check(uid);
    final data = (await document(uid, project)
            .get()
            .timeout(const Duration(seconds: 15)))
        .data();
    check(uid);
    final name = data?['worksheet'];
    return name is String && name.trim().isNotEmpty ? name : null;
  }

  static Future<void> save(String uid, String project, String name) async {
    check(uid);
    if (name.trim().isEmpty || name.length > 31) {
      throw ArgumentError('Guia inválida.');
    }
    await document(uid, project)
        .set({'worksheet': name}).timeout(const Duration(seconds: 15));
    check(uid);
  }
}
