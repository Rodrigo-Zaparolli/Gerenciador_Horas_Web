import '../../domain/models/project_model.dart';

int receivedMinutes(String value) {
  final match = RegExp(r'^(\d{1,5}):([0-5]\d)$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException('Informe as horas no formato HH:mm.');
  }
  return int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

String receivedHours(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

DateTime? receivedDate(String? value) {
  final match =
      RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value?.trim() ?? '');
  if (match == null) return null;
  final date = DateTime(
      int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
  return date.day == int.parse(match[1]!) && date.month == int.parse(match[2]!)
      ? date
      : null;
}

ProjectModel receivedProject(
    {required String request,
    required String client,
    required String type,
    required String leader,
    required DateTime receivedAt,
    required String hourType,
    bool requireMetadata = true,
    required List<Map<String, String>> steps}) {
  bool valid(String value) =>
      value.trim().isNotEmpty &&
      !RegExp(r'^(?:[-—]|selecione(?:\s.*)?|n[aã]o informado|n[aã]o definido)$',
              caseSensitive: false)
          .hasMatch(value.trim());
  if (!RegExp(r'^\d+$').hasMatch(request) ||
      (requireMetadata && (!valid(client) || !valid(type) || !valid(leader))) ||
      steps.isEmpty) {
    throw const FormatException(
        'Confira solicitação, cliente, tipo, líder e selecione ao menos um trabalho.');
  }
  final ids = <String>{};
  var total = 0;
  final tasks = <TaskModel>[];
  for (final step in steps) {
    final id = step['id']?.trim() ?? '';
    final name = step['name']?.trim() ?? '';
    if (!RegExp(r'^\d+$').hasMatch(id) || !ids.add(id) || !valid(name)) {
      throw const FormatException(
          'Cada etapa precisa de nome e número de trabalho válido, sem repetição.');
    }
    final minutes = receivedMinutes(step['hours'] ?? '');
    total += minutes;
    tasks.add(TaskModel(
        subId: id,
        stage: name,
        status: 'INI_PRO',
        startDate: receivedAt,
        planStart: receivedDate(step['start']),
        planEnd: receivedDate(step['end']),
        estimatedHours: receivedHours(minutes),
        hourType: hourType,
        edeskSolicitacao: request,
        edeskIdTrabalho: id));
  }
  return ProjectModel(
      id: request,
      id2: '',
      client: client.trim(),
      serviceType: type.trim(),
      stage: tasks.first.stage,
      task: '',
      status: 'INI_PRO',
      startDate: receivedAt,
      estimatedHours: receivedHours(total),
      leader: leader.trim(),
      hourType: hourType,
      subTasks: tasks);
}

class ReceivedImportPlan {
  const ReceivedImportPlan(this.patch, this.added, this.keys);
  final Map<String, dynamic> patch;
  final int added;
  final List<String> keys;
}

/// Append only unknown work identities. Existing metadata and tasks are intact.
ReceivedImportPlan planReceivedImport(ProjectModel incoming,
    Map<String, dynamic>? current, Set<String> imported) {
  final existingTasks = (current?['subTasks'] as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final existing = <String>{};
  for (final task in existingTasks) {
    final request = task['edeskSolicitacao']?.toString().trim();
    final number = task['subId']?.toString().trim() ?? '';
    final id = RegExp(r'^\d+$').hasMatch(number)
        ? number
        : task['edeskIdTrabalho']?.toString().trim() ?? '';
    existing.add(
        '${request == null || request.isEmpty ? incoming.id : request}/$id');
  }
  final added = <TaskModel>[];
  final keys = <String>[];
  for (final task in incoming.subTasks ?? <TaskModel>[]) {
    final key = '${incoming.id}/${task.edeskWorkNumber}';
    if (existing.contains(key) || imported.contains(key)) continue;
    if (existingTasks.any((old) => old['subId']?.toString() == task.subId)) {
      throw const FormatException(
          'Já existe uma etapa com esse número vinculada a outra solicitação. Confira no editor.');
    }
    existing.add(key);
    added.add(task);
    keys.add(key);
  }
  if (added.isEmpty) return const ReceivedImportPlan({}, 0, []);
  final previous = current == null
      ? 0
      : receivedMinutes(current['estimatedHours']?.toString() ?? '');
  if (current != null && existingTasks.isEmpty && previous > 0) {
    throw const FormatException(
        'O projeto existente tem horas previstas sem etapas vinculadas. Confira os trabalhos no editor antes de importar.');
  }
  final total = previous +
      added.fold<int>(
          0, (sum, task) => sum + receivedMinutes(task.estimatedHours));
  return ReceivedImportPlan({
    if (current == null) ...incoming.toJson(),
    'subTasks': [...existingTasks, ...added.map((task) => task.toJson())],
    'estimatedHours': receivedHours(total),
  }, added.length, keys);
}
