import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/work_audit.dart';

ProjectModel project() => ProjectModel(
        id: '226144',
        id2: '',
        client: 'Cliente',
        serviceType: 'Professional',
        stage: 'Implantação',
        task: '',
        status: 'TRAB',
        startDate: DateTime(2026, 10, 22),
        estimatedHours: '20:00',
        leader: '',
        hourType: 'Hs Cobradas',
        subTasks: [
          TaskModel(
              subId: '3',
              stage: 'Implantação Plugin',
              status: 'TRAB',
              startDate: DateTime(2026, 10, 22),
              planStart: DateTime(2026, 10, 1),
              planEnd: DateTime(2026, 10, 30),
              estimatedHours: '20:00',
              hourType: 'Hs Cobradas',
              edeskIdTrabalho: '2')
        ]);

void main() {
  test('Summary distinguishes incomplete reads, errors, differences and consultation', () {
    String summary(List<AuditFieldResult> fields, {bool errors = false}) =>
        auditSummary([fields], hasErrors: errors, interrupted: false);
    expect(summary([]), startsWith('Conferência parcial'));
    expect(summary(const [AuditFieldResult('name', 'Nome', '', 'Não consultado')]),
        startsWith('Conferência parcial'));
    expect(summary(const [AuditFieldResult('percentage', '', '100', 'Somente consulta')], errors: true),
        startsWith('Conferência parcial'));
    expect(summary(const [AuditFieldResult('name', 'A', 'B', 'Divergência')]),
        contains('divergências'));
    expect(summary(const [AuditFieldResult('percentage', '', '100', 'Somente consulta')]),
        startsWith('Consulta concluída: todos os campos'));
    expect(auditSummary([], hasErrors: false, interrupted: true),
        startsWith('Conferência interrompida'));
  });
  test('targets honor the edited work number and the task-specific request',
      () {
    final p = project();
    expect(projectAuditTargets([p]).single.toJson(), {
      'solicitacao': '226144',
      'trabalhos': ['3']
    });
    p.subTasks!.first.edeskSolicitacao = '999';
    expect(projectAuditTargets([p]).single.number, '999');
    expect(p.subTasks!.first.edeskIdTrabalho, '2');
  });
  test(
      'duplicate or invalid work identities are rejected, never silently skipped',
      () {
    final p = project();
    expect(() => projectAuditTargets([p, p]), throwsFormatException);
    p.subTasks!.first.subId = 'invalid';
    p.subTasks!.first.edeskIdTrabalho = null;
    expect(() => projectAuditTargets([p]), throwsFormatException);
  });
  test(
      'unknown fields cannot be reported as equal, and actual hours are not compared with estimates',
      () {
    final target = projectAuditTargets([project()]).single;
    final results = compareAuditWork(
        target.expected['3']!,
        {
          'name': 'Implantação Plugin',
          'status': 'Em andamento',
          'percentage': '70',
          'hours': '05:00'
        },
        auditFields.keys.toSet());
    expect(results.first.state, 'Igual');
    expect(results[1].state, 'Igual');
    expect(results[2].state, 'Não consultado');
    expect(results[4].state, 'Somente consulta');
    expect(results[5].state, 'Somente consulta');
  });
  test(
      'date normalization detects divergences and refuses invalid or ambiguous dates',
      () {
    final expected = {'start': '01/10/2026', 'end': '30/10/2026'};
    expect(
        compareAuditWork(expected, {'start': '1/10/2026', 'end': '31/10/2026'},
            {'start', 'end'}).map((r) => r.state),
        ['Igual', 'Divergência']);
    expect(
        compareAuditWork(expected, {'start': '31/02/2026'}, {'start'})
            .single
            .state,
        'Revisar data');
    expect(
        compareAuditWork({'status': 'EA'}, {'status': 'Em espera'}, {'status'})
            .single
            .state,
        'Revisar situação');
  });
}
