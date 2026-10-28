import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../../../core/platform/comment_paste.dart';
import '../../../core/platform/writing_review_input.dart';
import 'comment_writing_review.dart';

Future<void> showCommentSpellingDialog(
    BuildContext context, quill.QuillController controller,
    {required bool Function() canEdit}) async {
  if (!canEdit()) return;
  final original = controller.document.toPlainText();
  final revised = await showDialog<String>(
      context: context, builder: (_) => _SpellingDialog(text: original));
  if (revised == null || !context.mounted || !canEdit()) return;
  if (controller.document.toPlainText() != original) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text(
            'O coment\u00e1rio mudou durante a revis\u00e3o. Abra o corretor novamente.')));
    return;
  }
  try {
    applyCommentWritingReview(controller, normalizeCommentPastedText(revised));
  } on FormatException catch (error) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

class _SpellingDialog extends StatefulWidget {
  const _SpellingDialog({required this.text});
  final String text;
  @override
  State<_SpellingDialog> createState() => _SpellingState();
}

class _SpellingState extends State<_SpellingDialog> {
  late String revised = widget.text;
  bool answered = false;
  void finish(String? result) {
    if (!mounted || answered) return;
    answered = true;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) answered = true;
      },
      child: AlertDialog(
          title: const Text('Corretor do coment\u00e1rio'),
          content: SizedBox(
              width: 640,
              height: MediaQuery.sizeOf(context).height * .5,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Clique com o bot\u00e3o direito nas palavras sublinhadas para ver sugest\u00f5es em portugu\u00eas. Ative o corretor de portugu\u00eas no Edge ou Chrome.'),
                    const SizedBox(height: 12),
                    Expanded(
                        child: writingReviewInput(
                            text: widget.text,
                            onChanged: (value) => revised = value,
                            foreground: Theme.of(context).colorScheme.onSurface,
                            background: Theme.of(context).colorScheme.surface)),
                  ])),
          actions: [
            TextButton(
                onPressed: () => finish(null), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => finish(revised),
                child: const Text('Aplicar corre\u00e7\u00f5es')),
          ]));
}
