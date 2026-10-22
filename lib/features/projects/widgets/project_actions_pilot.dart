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
      required this.onEmail, this.onAudit});
  final VoidCallback? onAudit;
  final bool hasFolder, hasExcel;
  final VoidCallback onFolder,
      onExcel,
      onEditSpreadsheet,
      onEditWork,
      onChecklist,
      onComment,
      onEmail;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'A\u00e7\u00f5es do projeto',
        icon: const Icon(Icons.more_horiz, size: 22),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
        onSelected: (value) {
          if ((value == 'folder' && !hasFolder) ||
              (['open', 'spreadsheet'].contains(value) && !hasExcel)) {
            return;
          }
          final actions = <String, VoidCallback>{
            'folder': onFolder,
            'open': onExcel,
            'spreadsheet': onEditSpreadsheet,
            'work': onEditWork,
            'check': onChecklist,
            'comment': onComment,
            'email': onEmail,
            if (onAudit != null) 'audit': onAudit!,
          };
          actions[value]?.call();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'folder',
              enabled: hasFolder,
              child: _ActionMenuLabel(Icons.folder_outlined, 'Abrir pasta',
                  enabled: hasFolder)),
          PopupMenuItem(
              value: 'open',
              enabled: hasExcel,
              child: _ActionMenuLabel(
                  Icons.table_chart_outlined, 'Abrir planilha no Excel',
                  enabled: hasExcel)),
          PopupMenuItem(
              value: 'spreadsheet',
              enabled: hasExcel,
              child: _ActionMenuLabel(
                  Icons.edit_note_rounded, 'Editar planilha no sistema',
                  enabled: hasExcel)),
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'work',
              child: _ActionMenuLabel(Icons.edit_outlined, 'Editar trabalho')),
          const PopupMenuItem(
              value: 'check',
              child: _ActionMenuLabel(Icons.checklist_rounded, 'Checklist')),
          const PopupMenuItem(
              value: 'comment',
              child: _ActionMenuLabel(
                  Icons.chat_bubble_outline_rounded, 'Coment\u00e1rios')),
          const PopupMenuItem(
              value: 'email',
              child: _ActionMenuLabel(Icons.mail_outline_rounded, 'E-mails')),
          if (onAudit != null) const PopupMenuItem(value:'audit',
            child:_ActionMenuLabel(Icons.fact_check_outlined, 'Conferir este projeto no E-Desk')),
        ],
      );
}

class _ActionMenuLabel extends StatelessWidget {
  const _ActionMenuLabel(this.icon, this.label, {this.enabled = true});
  final bool enabled;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon == Icons.mail_outline_rounded)
          CustomPaint(
              size: const Size.square(20),
              painter:
                  _MenuEmailPainter(Theme.of(context).colorScheme.onSurface))
        else
          Icon(icon,
              size: 20,
              color: enabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).disabledColor),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ]);
}

class _MenuEmailPainter extends CustomPainter {
  const _MenuEmailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
        size.width * .08, size.height * .2, size.width * .84, size.height * .6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    canvas.drawPath(
        Path()
          ..moveTo(rect.left + 1, rect.top + 1)
          ..lineTo(rect.center.dx, rect.center.dy + 1)
          ..lineTo(rect.right - 1, rect.top + 1),
        paint);
  }

  @override
  bool shouldRepaint(covariant _MenuEmailPainter oldDelegate) =>
      oldDelegate.color != color;
}
