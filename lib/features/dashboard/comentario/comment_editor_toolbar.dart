import 'package:flutter/material.dart';

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
