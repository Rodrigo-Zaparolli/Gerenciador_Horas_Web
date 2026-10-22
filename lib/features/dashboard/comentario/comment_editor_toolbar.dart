import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Only offer families shipped with the app; system fonts are unavailable to
/// the web canvas. Keep a saved legacy family visible until the user changes it.
class CommentFontPicker extends StatelessWidget {
  const CommentFontPicker(
      {super.key,
      required this.value,
      required this.controller,
      required this.editorFocus,
      required this.onChanged});

  static const families = ['Roboto', 'Lato', 'Noto Serif', 'Roboto Mono'];
  final String value;
  final quill.QuillController controller;
  final FocusNode editorFocus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        key: const ValueKey('comment-font-picker'),
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [if (!families.contains(value)) value, ...families]
            .map((font) => DropdownMenuItem(
                value: font,
                child: Text(font,
                    style: TextStyle(fontFamily: font, fontSize: 11))))
            .toList(),
        onChanged: (font) {
          if (font == null) return;
          // Change only the font, preserving size, emphasis, color and selection.
          controller.formatSelection(
              quill.Attribute.clone(quill.Attribute.font, font));
          onChanged(font);
          editorFocus.requestFocus();
        },
      );
}

/// Formatting can scroll, but the three project indicators stay visible.
class CommentEditorToolbar extends StatelessWidget {
  const CommentEditorToolbar(
      {super.key, required this.formatting, required this.indicators});
  final Widget formatting;
  final List<Widget> indicators;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: formatting)),
        const VerticalDivider(width: 8, indent: 8, endIndent: 8),
        ...indicators,
      ]);
}
