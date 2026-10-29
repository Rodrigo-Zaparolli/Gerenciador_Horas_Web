import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Bundled families render in Flutter. Times New Roman uses the system font
/// in the native HTML editor; its menu label uses the regular UI font.
class CommentFontPicker extends StatelessWidget {
  const CommentFontPicker(
      {super.key,
      required this.value,
      required this.controller,
      required this.editorFocus,
      required this.onChanged});

  static const bundledFamilies = [
    'Roboto',
    'Lato',
    'Noto Serif',
    'Roboto Mono'
  ];
  static const families = [...bundledFamilies, 'Times New Roman'];
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
                    style: TextStyle(
                        fontFamily: font == 'Times New Roman' ? null : font,
                        fontSize: 11))))
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
