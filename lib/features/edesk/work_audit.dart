import '../../domain/models/project_model.dart';

const auditFields = <String, String>{
  'name': 'Nome do trabalho',
  'status': 'Situação',
  'start': 'Início ajustado (Fases)',
  'end': 'Fim ajustado (Fases)',
  'percentage': '% realizado',
  'hours': 'Horas trabalhadas',
  'estimatedHours': 'Horas previstas',
  'remainingHours': 'Horas restantes',
  'overrunHours': 'Horas excedentes',
  'completed': 'Trabalho concluído',
  'phaseName': 'Fase consultada',
};

String auditNormalized(String value) {
  var result = value.toLowerCase().trim();
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ç': 'c'
  };
  replacements.forEach((from, to) => result = result.replaceAll(from, to));
  return result.replaceAll(RegExp(r'\s+'), ' ');
}

String? auditStatus(String value) => switch (auditNormalized(value)) {
      'ini_pro' ||
      'não iniciado' ||
      'nao iniciado' ||
      'nao iniciada' ||
      'aberto' ||
      'aberta' =>
        'inicio',
      'em andamento' ||
      'andamento' ||
      'exe_pro' ||
      'trab_exe' ||
      'trab' =>
        'andamento',
      'trab_stop' || 'parado' || 'parada' || 'pausado' || 'pausada' => 'parado',
      'trab_fim' ||
      'finalizado' ||
      'finalizada' ||
      'concluido' ||
      'concluida' ||
      'encerrado' ||
      'encerrada' =>
        'fim',
      _ => null,
    };

String auditDate(DateTime? date) => date == null
    ? ''
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class AuditTarget {
  AuditTarget(this.number);
  final String number;
  final Map<String, Map<String, String>> expected = {};
  Map<String, dynamic> toJson() =>
      {'solicitacao': number, 'trabalhos': expected.keys.toList()};
}

List<AuditTarget> projectAuditTargets(List<ProjectModel> projects,
    {ProjectModel? selectedProject}) {
  final targets = <String, AuditTarget>{};
  for (final project
      in selectedProject == null ? projects : [selectedProject]) {
    final tasks = project.subTasks ?? <TaskModel>[];
    if (tasks.isEmpty) {
      if (!RegExp(r'^\d+$').hasMatch(project.id.trim())) {
        throw const FormatException(
            'O projeto precisa de um número de solicitação válido.');
      }
      targets.putIfAbsent(
          project.id.trim(), () => AuditTarget(project.id.trim()));
    }
    for (final task in tasks) {
      final number = (task.edeskSolicitacao?.trim().isNotEmpty == true
              ? task.edeskSolicitacao
              : project.id)!
          .trim();
      final work = task.edeskWorkNumber;
      if (!RegExp(r'^\d+$').hasMatch(number) ||
          !RegExp(r'^\d+$').hasMatch(work)) {
        throw FormatException(
            '${project.client}: confira os números da solicitação e do trabalho ${task.stage}.');
      }
      final target = targets.putIfAbsent(number, () => AuditTarget(number));
      if (target.expected.containsKey(work)) {
        throw FormatException(
            'Trabalho $number/$work repetido nos projetos selecionados.');
      }
      target.expected[work] = {
        'name': task.stage,
        'status': task.status,
        'start': auditDate(task.planStart),
        'end': auditDate(task.planEnd),
        'estimatedHours': task.estimatedHours,
        if (auditStatus(task.status) != null)
          'completed': auditStatus(task.status) == 'fim' ? 'Sim' : 'Nao',
      };
    }
  }
  return targets.values.toList();
}

class AuditFieldResult {
  const AuditFieldResult(this.field, this.app, this.edesk, this.state);
  final String field, app, edesk, state;
}

String auditWorkSummary(List<AuditFieldResult> fields, {String? error}) {
  if (error != null ||
      fields.isEmpty ||
      fields.any((f) => f.state == 'N\u00e3o consultado')) {
    return 'Confer\u00eancia parcial';
  }
  if (fields.any((f) => f.state == 'Diverg\u00eancia')) {
    return 'Diverg\u00eancias encontradas';
  }
  if (fields.any((f) => f.state != 'Igual' && f.state != 'Somente consulta')) {
    return 'Dados para revisar';
  }
  return 'Consulta conclu\u00edda';
}

String auditSummary(Iterable<List<AuditFieldResult>> rows,
    {required bool hasErrors, required bool interrupted}) {
  if (interrupted) {
    return 'Conferência interrompida. Resultados já obtidos foram mantidos.';
  }
  final fields = rows.expand((row) => row).toList();
  final missing =
      fields.where((field) => field.state == 'Não consultado').length;
  if (hasErrors || fields.isEmpty || missing > 0) {
    return 'Conferência parcial: há dados que não puderam ser consultados. '
        'Confira os avisos de cada trabalho. Nenhum dado foi alterado.';
  }
  if (fields.any(
      (field) => field.state != 'Igual' && field.state != 'Somente consulta')) {
    return 'Consulta concluída com divergências ou dados para revisar. '
        'Nenhum dado foi alterado.';
  }
  return 'Consulta concluída: todos os campos selecionados foram lidos. '
      'Nenhum dado foi alterado.';
}

List<AuditFieldResult> compareAuditWork(Map<String, String> expected,
        Map<String, dynamic> actual, Set<String> fields) =>
    [
      for (final field in fields)
        AuditFieldResult(
            field,
            expected[field] ?? '',
            actual[field]?.toString() ?? '',
            _compare(
                field, expected[field] ?? '', actual[field]?.toString() ?? '')),
    ];

String _compare(String field, String expected, String actual) {
  if (actual.trim().isEmpty) return 'Não consultado';
  if (expected.trim().isEmpty &&
      !const [
        'hours',
        'estimatedHours',
        'remainingHours',
        'overrunHours',
        'start',
        'end'
      ].contains(field)) {
    return 'Somente consulta';
  }
  if (const ['hours', 'estimatedHours', 'remainingHours', 'overrunHours']
      .contains(field)) {
    int? minutes(String value) {
      final match = RegExp(r'^(\d+):([0-5]\d)$').firstMatch(value.trim());
      return match == null
          ? null
          : int.parse(match[1]!) * 60 + int.parse(match[2]!);
    }

    final right = minutes(actual);
    if (right == null) return 'Revisar horas';
    if (expected.trim().isEmpty) return 'Somente consulta';
    final left = minutes(expected);
    if (left == null) return 'Revisar horas';
    return left == right ? 'Igual' : 'Diverg\u00eancia';
  }
  if (field == 'status') {
    final left = auditStatus(expected), right = auditStatus(actual);
    if (left == null || right == null) return 'Revisar situação';
    return left == right ? 'Igual' : 'Divergência';
  }
  if (field == 'start' || field == 'end') {
    String? normalizeDate(String value) {
      final match =
          RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value.trim());
      if (match == null) return null;
      final date = DateTime(
          int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
      if (date.day != int.parse(match[1]!) ||
          date.month != int.parse(match[2]!)) {
        return null;
      }
      return auditDate(date);
    }

    final right = normalizeDate(actual);
    if (right == null) return 'Revisar data';
    if (expected.trim().isEmpty) return 'Somente consulta';
    final left = normalizeDate(expected);
    if (left == null) return 'Revisar data';
    return left == right ? 'Igual' : 'Divergência';
  }
  return auditNormalized(expected) == auditNormalized(actual)
      ? 'Igual'
      : 'Divergência';
}

String? auditWorkErrors(Map<String, dynamic> row, Set<String> fields) {
  final errors = <String>[
    if (row['error'] != null) row['error'].toString(),
    if (fields
            .any(const {'hours', 'remainingHours', 'overrunHours'}.contains) &&
        row['hoursError'] != null)
      row['hoursError'].toString(),
    if (fields.any(const {'start', 'end', 'phaseName'}.contains) &&
        row['phaseError'] != null)
      row['phaseError'].toString(),
  ];
  return errors.isEmpty ? null : errors.join('\n');
}
