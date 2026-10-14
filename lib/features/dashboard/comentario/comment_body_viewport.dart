import 'package:flutter/material.dart';

/// Allows the editor and attachments to remain reachable in short windows.
class CommentBodyViewport extends StatelessWidget {
  const CommentBodyViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        if (size.maxHeight >= 520) return child;
        return SingleChildScrollView(
          child: SizedBox(height: 520, width: size.maxWidth, child: child),
        );
      });
}
