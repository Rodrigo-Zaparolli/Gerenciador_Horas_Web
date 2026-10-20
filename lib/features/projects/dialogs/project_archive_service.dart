import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/archive_destination_store.dart';
import '../../../data/services/firebase_service.dart';
import '../../../data/services/native_local_files_service.dart';

class ProjectArchiveService {
  String? get uid => FirebaseAuth.instance.currentUser?.uid;
  String? get email => FirebaseAuth.instance.currentUser?.email;
  bool get allowed => PilotFeatureAccess.allows(uid: uid, email: email);
  Stream<void> get accountChanges =>
      FirebaseAuth.instance.authStateChanges().map((_) {});
  Future<ArchiveDestination?> loadDestination(String owner) =>
      FirebaseArchiveDestinationStore().load(owner);
  Future<void> saveDestination(String owner, ArchiveDestination value) =>
      FirebaseArchiveDestinationStore().save(owner, value);
  Future<void> checkCompleted(String owner, String projectId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(owner)
        .collection('completed_projects')
        .doc(projectId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    if (uid != owner ||
        !allowed ||
        !doc.exists ||
        doc.data()?['status'] != 'TRAB_FIM') {
      throw StateError('Esta ação exige um projeto finalizado.');
    }
  }

  Future<Map<String, dynamic>> call(String action,
          {String? reference,
          String? destination,
          String? excelReference,
          String? sourceReference,
          String? operation}) =>
      NativeLocalFiles.call(action,
          reference: reference,
          destination: destination,
          excelReference: excelReference,
          sourceReference: sourceReference,
          operation: operation);
  Future<void> applyMove(String projectId, Map<String, dynamic> result) =>
      FirebaseService().applyProjectFolderMove(projectId, result);
}
