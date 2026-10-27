import 'package:flutter/material.dart';

class WorkbookConfirmation extends StatefulWidget {
  const WorkbookConfirmation(
      {super.key,
      required this.title,
      required this.message,
      required this.confirmLabel,
      this.cancelLabel = 'Cancelar'});
  final String title, message, confirmLabel, cancelLabel;
  @override
  State<WorkbookConfirmation> createState() => _WorkbookConfirmationState();
}

class _WorkbookConfirmationState extends State<WorkbookConfirmation> {
  bool answered = false;
  void finish(bool result) {
    if (answered) return;
    answered = true;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) answered = true;
      },
      child: AlertDialog(
          title: Text(widget.title),
          content: Text(widget.message),
          actions: [
            TextButton(
                onPressed: () => finish(false),
                child: Text(widget.cancelLabel)),
            FilledButton(
                onPressed: () => finish(true),
                child: Text(widget.confirmLabel)),
          ]));
}
