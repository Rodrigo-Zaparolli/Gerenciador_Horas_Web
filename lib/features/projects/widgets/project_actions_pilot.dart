import 'package:flutter/material.dart';

class ProjectActionsPilot extends StatelessWidget {
  const ProjectActionsPilot(
      {super.key,
      required this.hasFolder,
      required this.hasExcel,
      required this.onFolder,
      required this.onExcel,
      required this.onEditSpreadsheet,
      required this.onEditWork,
      required this.onChecklist,
      required this.onComment,
      required this.onEmail});
  final bool hasFolder, hasExcel;
  final VoidCallback onFolder,
      onExcel,
      onEditSpreadsheet,
      onEditWork,
      onChecklist,
      onComment,
      onEmail;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton.icon(
            onPressed: hasFolder ? onFolder : null,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            icon: const Icon(Icons.folder_outlined, size: 17),
            label: const Text('Pasta', style: TextStyle(fontSize: 12))),
        PopupMenuButton<String>(
            enabled: hasExcel,
            tooltip: 'Planilha do projeto',
            onSelected: (value) =>
                value == 'open' ? onExcel() : onEditSpreadsheet(),
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Abrir no Excel')),
                  PopupMenuItem(value: 'edit', child: Text('Editar no sistema'))
                ],
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.table_chart_outlined,
                      size: 17,
                      color: hasExcel
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).disabledColor),
                  const SizedBox(width: 4),
                  Text('Planilha',
                      style: TextStyle(
                          fontSize: 12,
                          color: hasExcel
                              ? null
                              : Theme.of(context).disabledColor)),
                  const Icon(Icons.expand_more, size: 16)
                ]))),
        PopupMenuButton<String>(
            tooltip: 'Mais ações',
            icon: const Icon(Icons.more_horiz, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 180),
            onSelected: (value) => {
                  'work': onEditWork,
                  'check': onChecklist,
                  'comment': onComment,
                  'email': onEmail
                }[value]
                    ?.call(),
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'work', child: _ActionMenuLabel(Icons.edit_outlined, 'Editar trabalho')),
                  PopupMenuItem(value: 'check', child: _ActionMenuLabel(Icons.checklist_rounded, 'Checklist')),
                  PopupMenuItem(value: 'comment', child: _ActionMenuLabel(Icons.chat_bubble_outline_rounded, 'Comentários')),
                  PopupMenuItem(value: 'email', child: _ActionMenuLabel(Icons.mail_outline_rounded, 'E-mails'))
                ]),
      ]);
}

class _ActionMenuLabel extends StatelessWidget {
  const _ActionMenuLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (icon == Icons.mail_outline_rounded)
      CustomPaint(size: const Size.square(20), painter: _MenuEmailPainter(Theme.of(context).colorScheme.onSurface))
    else
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
    const SizedBox(width: 12),
    Text(label),
  ]);
}

class _MenuEmailPainter extends CustomPainter {
  const _MenuEmailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke
      ..strokeWidth = 1.6..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(size.width * .08, size.height * .2, size.width * .84, size.height * .6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    canvas.drawPath(Path()..moveTo(rect.left + 1, rect.top + 1)
      ..lineTo(rect.center.dx, rect.center.dy + 1)
      ..lineTo(rect.right - 1, rect.top + 1), paint);
  }

  @override
  bool shouldRepaint(covariant _MenuEmailPainter oldDelegate) => oldDelegate.color != color;
}
