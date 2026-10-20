import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/pilot_feature_access.dart';

class ArchiveDestination {
  const ArchiveDestination(this.path, {this.reference});
  final String path;
  final String? reference;
  String get destination => reference ?? path;
  static const ownerPath =
      r'C:\Users\rodrigo.zaparolli\OneDrive - Cyncly\Documentos\Projetos Finalizados';
  static String suggestion(String? email) =>
      email?.trim().toLowerCase() == PilotFeatureAccess.ownerEmail
          ? ownerPath
          : '';

  static bool validPath(String path) =>
      path.length <= 4096 &&
      !RegExp(r'[\x00-\x1f]').hasMatch(path) &&
      (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
          RegExp(r'^\\\\[^\\]+\\[^\\]+').hasMatch(path));

  static String pathOf(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'desktop-folder' &&
            uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : value;
  }

  static ArchiveDestination? fromData(Map<String, dynamic>? data, String uid) {
    final destination = data?['destination'];
    if (destination is! String || destination.isEmpty) return null;
    final path = pathOf(destination);
    if (!validPath(path)) return null;
    final uri = Uri.tryParse(destination);
    final native = uri?.scheme == 'desktop-folder' &&
        uri?.host == 'local' &&
        uri!.pathSegments.length == 3 &&
        uri.pathSegments.first == uid;
    return ArchiveDestination(path, reference: native ? destination : null);
  }

  Map<String, dynamic> toData() {
    if (!validPath(path))
      throw ArgumentError(
          'Informe um caminho completo do Windows ou selecione a pasta.');
    if (reference != null && pathOf(reference!) != path) {
      throw ArgumentError(
          'O caminho mudou. Selecione novamente a pasta para autorizar o novo destino.');
    }
    return {'destination': destination, 'path': path};
  }
}

abstract class ArchiveDestinationStore {
  String? get currentUserId;
  String? get currentEmail;
  Future<ArchiveDestination?> load(String uid);
  Future<void> save(String uid, ArchiveDestination destination);
}

class FirebaseArchiveDestinationStore implements ArchiveDestinationStore {
  @override
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;
  @override
  String? get currentEmail => FirebaseAuth.instance.currentUser?.email;
  void check(String uid) {
    if (uid.isEmpty || currentUserId != uid)
      throw StateError('A conta mudou. Abra as configurações novamente.');
  }

  DocumentReference<Map<String, dynamic>> document(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('configuracoes')
          .doc('project_archive');
  @override
  Future<ArchiveDestination?> load(String uid) async {
    check(uid);
    final value =
        (await document(uid).get().timeout(const Duration(seconds: 15))).data();
    check(uid);
    return ArchiveDestination.fromData(value, uid);
  }

  @override
  Future<void> save(String uid, ArchiveDestination destination) async {
    check(uid);
    if (destination.reference != null &&
        ArchiveDestination.fromData(destination.toData(), uid)?.reference ==
            null) {
      throw ArgumentError(
          'O vínculo da pasta pertence a outra conta. Selecione novamente.');
    }
    await document(uid).set({
      ...destination.toData(),
      'updatedAt': FieldValue.serverTimestamp()
    }).timeout(const Duration(seconds: 15));
    check(uid);
  }
}
