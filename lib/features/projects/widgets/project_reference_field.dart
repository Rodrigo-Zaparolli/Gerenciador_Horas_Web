import 'package:flutter/material.dart';
import '../../../data/services/browser_local_files_service.dart';

/// Keeps the persisted capability reference out of the user-facing field.
class ProjectReferenceField extends StatefulWidget {
  const ProjectReferenceField(
      {super.key,
      required this.controller,
      required this.decoration,
      this.style,
      this.readOnly = false,
      this.onTap});
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final bool readOnly;
  final VoidCallback? onTap;
  @override
  State<ProjectReferenceField> createState() => _ProjectReferenceFieldState();
}

class _ProjectReferenceFieldState extends State<ProjectReferenceField> {
  final display = TextEditingController();
  @override
  void initState() {
    super.initState();
    sync();
    widget.controller.addListener(sync);
  }

  void sync() {
    final label = BrowserLocalFiles.label(widget.controller.text);
    if (display.text != label) display.text = label;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ProjectReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(sync);
      widget.controller.addListener(sync);
      sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(sync);
    display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = BrowserLocalFiles.isReference(widget.controller.text);
    return TextField(
        controller: display,
        style: widget.style,
        readOnly: widget.readOnly || local,
        onTap: widget.onTap,
        onChanged: (value) => widget.controller.text = value,
        decoration: widget.decoration.copyWith(
          helperText:
              local ? 'Arquivo ou pasta local' : widget.decoration.helperText,
          prefixIcon: local
              ? IconButton(
                  tooltip: 'Remover vínculo',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => widget.controller.clear())
              : widget.decoration.prefixIcon,
        ));
  }
}
