import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_appearance.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/services/project_update_service.dart';
import '../../../domain/models/deadline_alert.dart';

class DashboardAlertsModal extends StatelessWidget {
  const DashboardAlertsModal(
      {super.key,
      required this.deadlines,
      required this.updates,
      this.updatesUnavailable = false});
  final List<DeadlineAlert> deadlines;
  final List<PendingProjectUpdate> updates;
  final bool updatesUnavailable;
  static Future<String?> show(BuildContext context,
          List<DeadlineAlert> deadlines, List<PendingProjectUpdate> updates,
          {bool updatesUnavailable = false}) =>
      showDialog<String>(
          context: context,
          builder: (_) => DashboardAlertsModal(
              deadlines: deadlines,
              updates: updates,
              updatesUnavailable: updatesUnavailable));

  Widget _section(String title, IconData icon, int count) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: AppPalette.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text('$title ($count)',
                  style: TextStyle(
                      color: AppPalette.text, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _entry(BuildContext context,
      {required String title,
      required String description,
      required String badge,
      required bool overdue,
      required String action,
      required String label}) {
    final color = overdue ? AppPalette.danger : AppPalette.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppPalette.field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.border.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: AppPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(description,
            style: TextStyle(color: AppPalette.secondary, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(badge,
                      style: TextStyle(color: color, fontSize: 11))),
              OutlinedButton(
                  onPressed: () => Navigator.pop(context, action),
                  child: Text(label)),
            ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
        child: SizedBox(
            width: math.min(760, size.width - 32),
            child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * .85),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      child: Row(children: [
                        Icon(Icons.notifications_active_outlined,
                            color: AppPalette.warning),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Central de alertas',
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  deadlines.isEmpty && updates.isEmpty
                                      ? 'Nenhum alerta de prazo encontrado'
                                      : '${deadlines.length + updates.length} pendências precisam de atenção',
                                  style: TextStyle(
                                      color: AppPalette.secondary,
                                      fontSize: 12)),
                            ])),
                        IconButton(
                            tooltip: 'Fechar alertas',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ])),
                  Divider(height: 1, color: AppPalette.border),
                  Flexible(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (updatesUnavailable)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Text(
                                          'Não foi possível verificar os comentários. Consulte novamente pelo sino.',
                                          style: TextStyle(
                                              color: AppPalette.warning,
                                              fontSize: 12))),
                                if (deadlines.isEmpty &&
                                    updates.isEmpty &&
                                    !updatesUnavailable)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 24),
                                      child: Text(
                                          'Nenhum alerta pendente no momento.')),
                                if (deadlines.isNotEmpty)
                                  _section('Prazos de projetos e etapas',
                                      Icons.event_outlined, deadlines.length),
                                for (final entry in deadlines)
                                  _entry(context,
                                      title: '${entry.client} · ${entry.id}',
                                      description:
                                          '${entry.stage.isEmpty ? entry.serviceType : entry.stage} · Vencimento: ${ProjectUpdateService.formatDate(entry.planEnd)}',
                                      badge: entry.differenceDays < 0
                                          ? '${-entry.differenceDays} dia(s) em atraso'
                                          : entry.differenceDays == 0
                                              ? 'Vence hoje'
                                              : 'Vence em ${entry.differenceDays} dia(s)',
                                      overdue: entry.differenceDays < 0,
                                      action: 'alerts',
                                      label: 'Ver na central'),
                                if (updates.isNotEmpty)
                                  _section(
                                      'Atualizações de comentários',
                                      Icons.chat_bubble_outline,
                                      updates.length),
                                for (final entry in updates)
                                  _entry(context,
                                      title:
                                          '${entry.project.client} · ${entry.project.id}',
                                      description:
                                          'Último comentário: ${ProjectUpdateService.formatDate(entry.comment.date)} · Atualizar até: ${ProjectUpdateService.formatDate(entry.dueDate)}',
                                      badge: entry.overdueDays == 0
                                          ? 'Atualizar hoje'
                                          : '${entry.overdueDays} dia(s) em atraso',
                                      overdue: entry.overdueDays > 0,
                                      action: 'comment:${entry.project.id}',
                                      label: 'Comentar'),
                              ]))),
                  Divider(height: 1, color: AppPalette.border),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        if (updates.isNotEmpty)
                          OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(context, 'requests'),
                              child: const Text('Ver solicitações')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Entendi')),
                      ])),
                ]))));
  }
}
