import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'email_document.dart';

abstract class EmailDraftStore {
  String? get currentUserId;
  Future<Map<String, dynamic>?> loadDraft(
      String owner, String project, ProjectEmailKind kind);
  Future<Map<String, dynamic>?> loadTemplate(
      String owner, ProjectEmailKind kind);
  Future<void> saveDraft(String owner, String project, ProjectEmailKind kind,
      Map<String, dynamic> data);
  Future<void> saveTemplate(
      String owner, ProjectEmailKind kind, Map<String, dynamic> data);
}

class FirebaseEmailDraftStore implements EmailDraftStore {
  @override
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;
  void _check(String owner) {
    if (currentUserId != owner) throw StateError('A conta mudou.');
  }

  DocumentReference<Map<String, dynamic>> _draft(
          String owner, String project, ProjectEmailKind kind) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('projects')
          .doc(project)
          .collection('email_drafts')
          .doc(kind.name);
  DocumentReference<Map<String, dynamic>> _template(
          String owner, ProjectEmailKind kind) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('configuracoes')
          .doc('enterprise_email_${kind.name}');
  @override
  Future<Map<String, dynamic>?> loadDraft(
      String owner, String project, ProjectEmailKind kind) async {
    _check(owner);
    return (await _draft(owner, project, kind)
            .get()
            .timeout(const Duration(seconds: 15)))
        .data();
  }

  @override
  Future<Map<String, dynamic>?> loadTemplate(
      String owner, ProjectEmailKind kind) async {
    _check(owner);
    return (await _template(owner, kind)
            .get()
            .timeout(const Duration(seconds: 15)))
        .data();
  }

  @override
  Future<void> saveDraft(String owner, String project, ProjectEmailKind kind,
      Map<String, dynamic> data) async {
    _check(owner);
    await _draft(owner, project, kind)
        .set({...data, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> saveTemplate(
      String owner, ProjectEmailKind kind, Map<String, dynamic> data) async {
    _check(owner);
    await _template(owner, kind).set(data).timeout(const Duration(seconds: 15));
  }
}
