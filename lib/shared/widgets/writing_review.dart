import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/platform/writing_review_input.dart';

final _richTargets = <FocusNode, WritingReviewTargetState>{};

/// Register formatted editors that do not use Flutter's EditableText.
class WritingReviewTarget extends StatefulWidget {
  const WritingReviewTarget(
      {super.key,
      required this.focusNode,
      required this.readText,
      required this.applyText,
      required this.child});
  final FocusNode focusNode;
  final String Function() readText;
  final void Function(String) applyText;
  final Widget child;
  @override
  State<WritingReviewTarget> createState() => WritingReviewTargetState();
}

class WritingReviewTargetState extends State<WritingReviewTarget> {
  @override
  void initState() {
    super.initState();
    _richTargets[widget.focusNode] = this;
  }

  @override
  void dispose() {
    _richTargets.remove(widget.focusNode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

bool supportsWritingReview(EditableText field) =>
    !field.readOnly &&
    !field.obscureText &&
    field.autocorrect &&
    field.enableSuggestions &&
    [TextInputType.text, TextInputType.multiline, TextInputType.name]
        .contains(field.keyboardType);

class WritingReviewScope extends StatefulWidget {
  const WritingReviewScope(
      {super.key, required this.child, this.enabled = kIsWeb});
  final Widget child;
  final bool enabled;
  @override
  State<WritingReviewScope> createState() => _WritingReviewScopeState();
}

class _WritingReviewScopeState extends State<WritingReviewScope> {
  EditableTextState? plain;
  WritingReviewTargetState? rich;
  bool reviewing = false;
  bool queued = false;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(schedule);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(schedule);
    super.dispose();
  }

  void schedule() {
    if (queued) return;
    queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      queued = false;
      if (!mounted || reviewing) return;
      EditableTextState? nextPlain;
      WritingReviewTargetState? nextRich;
      for (final entry in _richTargets.entries) {
        if (entry.key.hasFocus && entry.value.mounted) nextRich = entry.value;
      }
      FocusManager.instance.primaryFocus?.context
          ?.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          final candidate = element.state as EditableTextState;
          if (supportsWritingReview(candidate.widget)) nextPlain = candidate;
          return false;
        }
        return true;
      });
      setState(() {
        plain = nextPlain;
        rich = nextRich;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> review() async {
    final field = plain;
    final editor = rich;
    final original = editor?.widget.readText() ?? field?.widget.controller.text;
    if (original == null || reviewing) return;
    setState(() => reviewing = true);
    var revised = original;
    final nav = Navigator.maybeOf(field?.context ?? editor!.context,
        rootNavigator: true);
    if (nav == null) {
      setState(() => reviewing = false);
      return;
    }
    final dialogContext = nav.context;
    try {
      final result = await showDialog<String>(
          context: dialogContext,
          builder: (context) => AlertDialog(
                title: const Text('Revisar escrita'),
                content: SizedBox(
                    width: 640,
                    height: MediaQuery.sizeOf(context).height * .55,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Clique com o botão direito nas palavras sublinhadas para ver sugestões. '
                              'O corretor de português precisa estar ativado no Edge ou Chrome.'),
                          const SizedBox(height: 12),
                          Expanded(
                              child: writingReviewInput(
                                  text: original,
                                  onChanged: (text) => revised = text,
                                  foreground:
                                      Theme.of(context).colorScheme.onSurface,
                                  background:
                                      Theme.of(context).colorScheme.surface)),
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, revised),
                      child: const Text('Aplicar correções'))
                ],
              ));
      if (result == null || result == original) return;
      if (editor != null &&
          editor.mounted &&
          editor.widget.readText() == original) {
        editor.widget.applyText(result);
      } else if (field != null &&
          field.mounted &&
          supportsWritingReview(field.widget) &&
          field.widget.controller.text == original) {
        field.userUpdateTextEditingValue(
            TextEditingValue(
                text: result,
                selection: TextSelection.collapsed(offset: result.length)),
            SelectionChangedCause.keyboard);
      } else if (mounted && nav.mounted) {
        ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(const SnackBar(
            content: Text(
                'O campo mudou durante a revisão. Abra a revisão novamente.')));
      }
    } on FormatException catch (error) {
      if (mounted && nav.mounted) {
        ScaffoldMessenger.maybeOf(nav.context)
            ?.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted)
        setState(() {
          reviewing = false;
          plain = null;
          rich = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (widget.enabled && !reviewing && (plain != null || rich != null))
          Positioned(
              right: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 80,
              child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(24),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: TextButton.icon(
                      onPressed: review,
                      icon: const Icon(Icons.spellcheck),
                      label: const Text('Revisar escrita')))),
      ]);
}
