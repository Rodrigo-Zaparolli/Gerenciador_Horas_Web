import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/pilot_feature_access.dart';
import '../../domain/models/project_model.dart';
import '../../features/edesk/received_work.dart';

class ReceivedWorkStore {
  ReceivedWorkStore({FirebaseFirestore? database, FirebaseAuth? auth})
      : _db = database ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<ProjectModel?> loadExisting(String request) async {
    final user = _auth.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      throw StateError('Recurso em teste restrito à conta autorizada.');
    }
    final root = _db.collection('users').doc(user!.uid);
    final closed = await root
        .collection('completed_projects')
        .where('id', isEqualTo: request)
        .get(const GetOptions(source: Source.server));
    final active = await root
        .collection('projects')
        .where('id', isEqualTo: request)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != user.uid) throw StateError('A conta mudou.');
    if (closed.docs.isNotEmpty) {
      throw StateError(
          'Este projeto está finalizado no app. Reabra-o antes de importar etapas.');
    }
    if (active.docs.length > 1) {
      throw StateError(
          'Há mais de um cadastro com essa solicitação. Confira no editor.');
    }
    return active.docs.isEmpty
        ? null
        : ProjectModel.fromJson(active.docs.single.data());
  }

  Future<int> import(ProjectModel project, {bool? expectedExisting}) async {
    final user = _auth.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      throw StateError('Recurso em teste restrito à conta autorizada.');
    }
    final db = _db;
    final root = db.collection('users').doc(user!.uid);
    final projects = root.collection('projects');
    final finished = root.collection('completed_projects');
    // Older records can have a document ID different from the solicitation.
    final matches = await projects
        .where('id', isEqualTo: project.id)
        .get(const GetOptions(source: Source.server));
    final closed = await finished
        .where('id', isEqualTo: project.id)
        .get(const GetOptions(source: Source.server));
    if (closed.docs.isNotEmpty) {
      throw StateError(
          'Este projeto está finalizado no app. Reabra-o antes de importar etapas.');
    }
    if (matches.docs.length > 1) {
      throw StateError(
          'Há mais de um projeto com essa solicitação. Confira os cadastros existentes.');
    }
    final target = matches.docs.isEmpty
        ? projects.doc(project.id)
        : matches.docs.single.reference;
    final markers = {
      for (final task in project.subTasks ?? <TaskModel>[])
        '${project.id}/${task.edeskWorkNumber}': root
            .collection('edesk_received')
            .doc('${project.id}-${task.edeskWorkNumber}')
    };
    return db.runTransaction((tx) async {
      final current = await tx.get(target);
      final canonical = target.id == project.id
          ? current
          : await tx.get(projects.doc(project.id));
      final completed = await tx.get(finished.doc(project.id));
      final legacyCompleted = target.id == project.id
          ? completed
          : await tx.get(finished.doc(target.id));
      final seen = <String>{};
      for (final entry in markers.entries) {
        if ((await tx.get(entry.value)).exists) seen.add(entry.key);
      }
      if (_auth.currentUser?.uid != user.uid) {
        throw StateError('A conta mudou durante o cadastro.');
      }
      if (completed.exists ||
          legacyCompleted.exists ||
          current.data()?['status'] == 'TRAB_FIM') {
        throw StateError(
            'O projeto está finalizado. Reabra-o antes de importar.');
      }
      if (target.id != project.id && canonical.exists) {
        throw StateError('A solicitação já tem outro cadastro no app.');
      }
      if (current.exists && current.data()?['id']?.toString() != project.id) {
        throw StateError(
            'O vínculo do cadastro existente não corresponde à solicitação. Confira no editor.');
      }
      if (expectedExisting == true && !current.exists) {
        throw StateError(
            'O projeto foi removido durante a conferência. Busque os dados novamente.');
      }
      final plan = planReceivedImport(project, current.data(), seen);
      if (plan.added == 0) return 0;
      if (expectedExisting == false && current.exists) {
        throw StateError(
            'O projeto foi cadastrado durante a conferência. Reabra os dados para conferir as etapas novas.');
      }
      if (current.exists) {
        tx.update(target, plan.patch);
      } else {
        tx.set(target, plan.patch);
      }
      for (final key in plan.keys) {
        tx.set(markers[key]!, {
          'request': project.id,
          'importedAt': FieldValue.serverTimestamp()
        });
      }
      return plan.added;
    });
  }
}
