import 'package:flutter/material.dart';

class SpreadsheetDialogHeader extends StatelessWidget {
  const SpreadsheetDialogHeader(
      {super.key,
      required this.projectId,
      required this.client,
      required this.filename,
      required this.serviceType,
      required this.onClose,
      this.moreActions,
      this.sheetAction});
  final String projectId, client, filename, serviceType;
  final VoidCallback? onClose;
  final Widget? moreActions;
  final Widget? sheetAction;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant))),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.table_chart_outlined,
                  color: colors.primary, size: 27)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Planilha do projeto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Tooltip(
                    message: filename,
                    child: Text(
                        '$projectId · ${client.isEmpty ? filename : client}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.onSurfaceVariant, fontSize: 12))),
              ])),
          if (serviceType.isNotEmpty && MediaQuery.sizeOf(context).width >= 700)
            Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .1),
                    border:
                        Border.all(color: colors.primary.withValues(alpha: .3)),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(serviceType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))),
          if (sheetAction != null) sheetAction!,
          if (moreActions != null) moreActions!,
          IconButton(
              tooltip: 'Fechar planilha',
              onPressed: onClose,
              icon: const Icon(Icons.close)),
        ]));
  }
}

class SpreadsheetDialogFooter extends StatelessWidget {
  const SpreadsheetDialogFooter(
      {super.key,
      required this.pendingCount,
      required this.synchronization,
      required this.actions});
  final int pendingCount;
  final String synchronization;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = pendingCount > 0 ? colors.tertiary : colors.onSurfaceVariant;
    final status = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(Icons.circle, size: 10, color: color)),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            pendingCount == 0
                ? 'Sem alterações pendentes'
                : '$pendingCount ${pendingCount == 1 ? 'alteração pendente' : 'alterações pendentes'}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 3),
        Tooltip(
            message: synchronization,
            child: Text(synchronization,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11, color: colors.onSurfaceVariant))),
      ])),
    ]);
    final buttons = Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant))),
        child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 850
                ? Row(children: [
                    Expanded(child: status),
                    const SizedBox(width: 20),
                    buttons
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [status, const SizedBox(height: 10), buttons])));
  }
}
