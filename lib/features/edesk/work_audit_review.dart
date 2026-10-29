import 'package:flutter/material.dart';
import '../../domain/models/project_model.dart';
import 'phase_audit_table.dart';
import 'work_audit.dart';
import 'work_audit_result_card.dart';

/// The same view is used in the app and the visual review fixtures.
class WorkAuditReview extends StatelessWidget {
  const WorkAuditReview(
      {super.key,
      this.project,
      required this.results,
      required this.options,
      required this.scopeControls,
      required this.busy,
      required this.message,
      required this.progress,
      required this.onRun,
      required this.onClose,
      required this.onAdjust,
      this.onStop});
  final ProjectModel? project;
  final List<PhaseAuditEntry> results;
  final Widget options, scopeControls;
  final bool busy;
  final String message, progress;
  final VoidCallback onRun, onClose;
  final VoidCallback? onStop;
  final void Function(String, List<AuditFieldResult>) onAdjust;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final phaseCount = results
        .map((r) {
          final phases = r.fields
              .where((f) => f.field == 'phaseName' && f.edesk.isNotEmpty);
          return phases.isEmpty
              ? null
              : '${r.reference.split('/').first}/${phases.first.edesk}';
        })
        .whereType<String>()
        .toSet()
        .length;
    final works = results.where((r) => r.reference.contains('/')).length;
    final review = results
        .where((r) =>
            auditWorkSummary(r.fields, error: r.error) !=
            'Consulta conclu\u00edda')
        .length;
    return PopScope(
        canPop: !busy,
        child: Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SizedBox(
                width: 1200,
                height: MediaQuery.sizeOf(context).height * .92,
                child: DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      Container(
                          padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                          decoration: BoxDecoration(
                              color: colors.primaryContainer
                                  .withValues(alpha: .40),
                              border: Border(
                                  bottom: BorderSide(
                                      color: colors.outlineVariant))),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: colors.primary,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Icon(Icons.fact_check_outlined,
                                        color: colors.onPrimary, size: 26)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('Confer\u00eancia do projeto',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                          project?.client ??
                                              'Selecione os projetos para consultar',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      if (project != null)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  _tag(context,
                                                      'Solicita\u00e7\u00e3o ${project!.id}'),
                                                  _tag(context,
                                                      project!.serviceType),
                                                ])),
                                    ])),
                                IconButton(
                                    tooltip: 'Fechar',
                                    onPressed: busy ? null : onClose,
                                    icon: const Icon(Icons.close)),
                              ])),
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Column(children: [
                                if (project == null)
                                  ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxHeight: 220),
                                      child: SingleChildScrollView(
                                          child: scopeControls)),
                                LayoutBuilder(
                                    builder: (context, box) => Wrap(
                                            spacing: 10,
                                            runSpacing: 8,
                                            children: [
                                              _stat(
                                                  context,
                                                  box.maxWidth,
                                                  Icons.work_outline,
                                                  'Trabalhos consultados',
                                                  '$works'),
                                              _stat(
                                                  context,
                                                  box.maxWidth,
                                                  Icons.account_tree_outlined,
                                                  'Fases identificadas',
                                                  '$phaseCount'),
                                              _stat(
                                                  context,
                                                  box.maxWidth,
                                                  Icons.rule_outlined,
                                                  'Resultados para revisar',
                                                  '$review'),
                                            ])),
                                ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    dense: true,
                                    title: const Text(
                                        'Op\u00e7\u00f5es da confer\u00eancia'),
                                    subtitle: const Text(
                                        'Datas das fases, horas e conclus\u00e3o dos trabalhos'),
                                    children: [
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: options)
                                    ]),
                                if (busy) ...[
                                  const LinearProgressIndicator(),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text(progress.isEmpty
                                          ? 'Aguardando a integra\u00e7\u00e3o...'
                                          : progress))
                                ],
                                if (message.isNotEmpty)
                                  Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: colors.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.info_outline,
                                                size: 18,
                                                color: colors.primary),
                                            const SizedBox(width: 10),
                                            Expanded(
                                                child: SelectableText(message,
                                                    style: theme
                                                        .textTheme.bodySmall))
                                          ])),
                                const Align(
                                    alignment: Alignment.centerLeft,
                                    child: TabBar(isScrollable: false, tabs: [
                                      Tab(
                                          text: 'Fases e datas',
                                          icon: Icon(
                                              Icons.account_tree_outlined,
                                              size: 18),
                                          iconMargin:
                                              EdgeInsets.only(bottom: 4)),
                                      Tab(
                                          text: 'Trabalhos e horas',
                                          icon: Icon(Icons.schedule_outlined,
                                              size: 18),
                                          iconMargin:
                                              EdgeInsets.only(bottom: 4))
                                    ])),
                                Expanded(
                                    child: TabBarView(children: [
                                  phaseCount == 0
                                      ? _empty(
                                          context,
                                          results.isEmpty
                                              ? 'Confira as fases deste projeto'
                                              : 'As fases ainda n\u00e3o foram consultadas',
                                          results.isEmpty
                                              ? 'Inicie a confer\u00eancia para comparar as datas do sistema com o E-Desk.'
                                              : 'A consulta n\u00e3o retornou as datas das fases. Os avisos da aba Trabalhos e horas mostram o motivo.',
                                          Icons.account_tree_outlined)
                                      : ListView(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          children: [
                                              PhaseAuditTable(
                                                  results: results,
                                                  busy: busy,
                                                  onAdjust: onAdjust)
                                            ]),
                                  results.isEmpty
                                      ? _empty(
                                          context,
                                          'Horas e situa\u00e7\u00e3o em um s\u00f3 lugar',
                                          'Ap\u00f3s a consulta, veja as horas previstas, trabalhadas e restantes de cada trabalho.',
                                          Icons.schedule_outlined)
                                      : ListView(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          children: [
                                              for (final result in results)
                                                WorkAuditResultCard(
                                                    showPhaseDates: false,
                                                    reference: result.reference,
                                                    fields: result.fields,
                                                    error: result.error)
                                            ]),
                                ])),
                              ]))),
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                              border: Border(
                                  top: BorderSide(
                                      color: colors.outlineVariant))),
                          child: LayoutBuilder(
                              builder: (context, box) => Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        if (box.maxWidth >= 650)
                                          Text(
                                              'Consulta sem altera\u00e7\u00f5es \u00b7 Ajustes exigem confirma\u00e7\u00e3o',
                                              style: theme.textTheme.bodySmall),
                                        if (busy && onStop != null)
                                          TextButton(
                                              onPressed: onStop,
                                              child: const Text(
                                                  'Interromper ap\u00f3s a consulta atual')),
                                        TextButton(
                                            onPressed: busy ? null : onClose,
                                            child: const Text('Fechar')),
                                        FilledButton.icon(
                                            onPressed: busy ? null : onRun,
                                            icon: Icon(results.isEmpty
                                                ? Icons.play_arrow_rounded
                                                : Icons.refresh),
                                            label: Text(results.isEmpty
                                                ? 'Iniciar confer\u00eancia'
                                                : 'Conferir novamente')),
                                      ]))),
                    ])))));
  }

  Widget _tag(BuildContext context, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall));

  Widget _stat(BuildContext context, double available, IconData icon,
      String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
        width: (available - 20) / 3,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: .6))),
            child: available < 520
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(value,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(label,
                            maxLines: 3,
                            style: Theme.of(context).textTheme.labelSmall),
                      ])
                : Row(children: [
                    Icon(icon, color: colors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(label,
                            style: Theme.of(context).textTheme.bodySmall)),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700))
                  ])));
  }

  Widget _empty(BuildContext context, String title, String description,
          IconData icon) =>
      Center(
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon,
                        size: 42, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Text(description, textAlign: TextAlign.center))
                  ]))));
}
