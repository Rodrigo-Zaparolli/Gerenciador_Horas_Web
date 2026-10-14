import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/project_model.dart';

class ProjectCommentUpdate {
  const ProjectCommentUpdate(this.id, this.date, this.text);
  final String id;
  final DateTime date;
  final String text;
}

class PendingProjectUpdate {
  const PendingProjectUpdate(this.project, this.comment, this.today);
  final ProjectModel project;
  final ProjectCommentUpdate comment;
  final DateTime today;
  DateTime get dueDate => ProjectUpdateService.nextUpdate(comment.date);
  int get overdueDays =>
      math.max(0, ProjectUpdateService.daysSince(comment.date, today) - 14);
}

/// Shared calendar rules and owner-scoped reads; no data migration or indexes.
class ProjectUpdateService {
  ProjectUpdateService(this.uid, {FirebaseFirestore? firestore})
      : _firestore = firestore;
  final String uid;
  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static DateTime? parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      final match =
          RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
      if (match != null) {
        return DateTime(
            int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
      }
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static int daysSince(DateTime last, DateTime today) => math.max(
      0,
      DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(last.year, last.month, last.day))
          .inDays);
  static DateTime nextUpdate(DateTime last) =>
      DateTime(last.year, last.month, last.day + 14);
  static bool isDue(DateTime last, DateTime today) =>
      daysSince(last, today) >= 14;
  static String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static ProjectCommentUpdate? latestSent(
      Iterable<Map<String, dynamic>> comments) {
    ProjectCommentUpdate? latest;
    for (final data in comments) {
      if (data['status']?.toString().trim().toLowerCase() != 'enviado')
        continue;
      DateTime? date;
      for (final field in [
        'enviadoEm',
        'dataHora',
        'criadoEm',
        'updatedAt',
        'data'
      ]) {
        date ??= parseDate(data[field]);
      }
      if (date != null && (latest == null || date.isAfter(latest.date))) {
        latest = ProjectCommentUpdate(data['id']?.toString() ?? '', date,
            data['comentario']?.toString() ?? '');
      }
    }
    return latest;
  }

  CollectionReference<Map<String, dynamic>> _comments(String projectId) => _db
      .collection('users')
      .doc(uid)
      .collection('projects')
      .doc(projectId.trim())
      .collection('comentarios_edesk');
  ProjectCommentUpdate? _latest(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      latestSent(snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}));

  Future<ProjectCommentUpdate?> lastComment(String projectId) async =>
      _latest(await _comments(projectId).get());
  Stream<ProjectCommentUpdate?> watchLastComment(String projectId) =>
      _comments(projectId).snapshots().map(_latest);

  Future<List<PendingProjectUpdate>> pending(
      Iterable<ProjectModel> projects, DateTime today) async {
    final active = projects.where((project) =>
        project.id.trim().isNotEmpty &&
        !['TRAB_FIM', 'CANCELADO', 'TRAB_CAN']
            .contains(project.status.trim().toUpperCase()) &&
        !project.client.toUpperCase().contains('CANCELADO'));
    final rows = await Future.wait(active.map((project) async {
      final comment = await lastComment(project.id);
      return comment != null && isDue(comment.date, today)
          ? PendingProjectUpdate(project, comment, today)
          : null;
    }));
    final result = rows.whereType<PendingProjectUpdate>().toList();
    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
  }
}
