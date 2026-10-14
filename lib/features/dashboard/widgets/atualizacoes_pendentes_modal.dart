import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../data/services/project_update_service.dart';

class AtualizacoesPendentesModal extends StatelessWidget {
  const AtualizacoesPendentesModal({super.key, required this.pending});
  final List<PendingProjectUpdate> pending;
  static const requestsAction = '__requests__';
  static Color get cyan => AppPalette.accent;
  static Color get muted => AppPalette.secondary;
  static Color get border => AppPalette.border;

  static Future<String?> show(
          BuildContext context, List<PendingProjectUpdate> pending) =>
      showDialog<String>(
          context: context,
          builder: (_) => AtualizacoesPendentesModal(pending: pending));

  Widget text(String value,
          {Color? color, double size = 12, bool bold = false}) =>
      Text(value,
          style: TextStyle(
              color: color ?? muted,
              fontSize: size,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400));

  Widget badge(PendingProjectUpdate row) {
    final color = row.overdueDays == 0 ? AppPalette.warning : AppPalette.danger;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: .5))),
        child: text(
            row.overdueDays == 0
                ? 'Vence hoje'
                : '${row.overdueDays} ${row.overdueDays == 1 ? 'dia' : 'dias'} em atraso',
            color: color,
            size: 11));
  }

  Widget row(BuildContext context, PendingProjectUpdate entry, bool wide) {
    final project = entry.project;
    final client =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      text(project.client, color: AppPalette.text, size: 13, bold: true),
      const SizedBox(height: 4),
      text('#${project.id} · ${project.serviceType}', size: 11),
    ]);
    final action = OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, project.id),
        style: OutlinedButton.styleFrom(
            foregroundColor: cyan,
            side: BorderSide(color: cyan),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        icon: const Icon(Icons.chat_bubble_outline, size: 16),
        label: const Text('Comentar', style: TextStyle(fontSize: 11)));
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: wide
            ? Row(children: [
                Expanded(child: client),
                SizedBox(
                    width: 125,
                    child: text(
                        ProjectUpdateService.formatDate(entry.comment.date),
                        color: AppPalette.text)),
                SizedBox(
                    width: 140,
                    child: text(ProjectUpdateService.formatDate(entry.dueDate),
                        color: AppPalette.text)),
                SizedBox(
                    width: 135,
                    child: Align(
                        alignment: Alignment.centerLeft, child: badge(entry))),
                SizedBox(width: 112, child: action),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                client,
                const SizedBox(height: 12),
                text(
                    'Último comentário: ${ProjectUpdateService.formatDate(entry.comment.date)}',
                    size: 11),
                const SizedBox(height: 4),
                text(
                    'Próxima atualização: ${ProjectUpdateService.formatDate(entry.dueDate)}',
                    size: 11),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [badge(entry), action]),
              ]));
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: border)),
        child: SizedBox(
            width: 1020,
            height: math.min(650, MediaQuery.sizeOf(context).height * .82),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color:
                                    AppPalette.warning.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(
                                Icons.notifications_active_outlined,
                                color: Color(0xFFFFBE38))),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              text('Atualizações pendentes',
                                  size: 20, color: AppPalette.text, bold: true),
                              const SizedBox(height: 5),
                              text(
                                  '${pending.length} ${pending.length == 1 ? 'solicitação precisa' : 'solicitações precisam'} de um novo comentário.',
                                  size: 12)
                            ])),
                        IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: muted))
                      ]),
                      const SizedBox(height: 16),
                      Divider(color: border, height: 1),
                      const SizedBox(height: 14),
                      text(
                          'O prazo para uma nova atualização é de 14 dias após o último comentário enviado ao E-Desk.'),
                      const SizedBox(height: 16),
                      Expanded(
                          child: LayoutBuilder(builder: (context, constraints) {
                        AppAppearance.watch(context);
                        final wide = constraints.maxWidth >= 820;
                        return Container(
                            decoration: BoxDecoration(
                                border: Border.all(color: border),
                                borderRadius: BorderRadius.circular(10)),
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [
                              if (wide)
                                Container(
                                    color: AppPalette.surface,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(children: [
                                      Expanded(
                                          child: text('Cliente / Solicitação',
                                              size: 11)),
                                      SizedBox(
                                          width: 125,
                                          child: text('Último comentário',
                                              size: 11)),
                                      SizedBox(
                                          width: 140,
                                          child: text('Próxima atualização',
                                              size: 11)),
                                      SizedBox(
                                          width: 135,
                                          child: text('Situação', size: 11)),
                                      const SizedBox(width: 112)
                                    ])),
                              Expanded(
                                  child: ListView.separated(
                                      itemCount: pending.length,
                                      separatorBuilder: (_, index) =>
                                          Divider(color: border, height: 1),
                                      itemBuilder: (context, index) =>
                                          row(context, pending[index], wide)))
                            ]));
                      })),
                      const SizedBox(height: 16),
                      text(
                          'Este aviso aparece a cada acesso ao dashboard enquanto houver pendências.',
                          size: 10),
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(spacing: 10, runSpacing: 8, children: [
                            OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Fechar')),
                            FilledButton.icon(
                                onPressed: () =>
                                    Navigator.pop(context, requestsAction),
                                style: FilledButton.styleFrom(
                                    backgroundColor: cyan,
                                    foregroundColor: AppPalette.onPrimary),
                                icon:
                                    const Icon(Icons.folder_outlined, size: 18),
                                label: const Text('Ver solicitações'))
                          ]))
                    ]))));
  }
}
