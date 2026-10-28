import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/shared/widgets/writing_review.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:gerenciador_horas/core/platform/comment_editor.dart';
import 'package:gerenciador_horas/core/platform/comment_paste.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_paste_action.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_editor_toolbar.dart';
import 'package:gerenciador_horas/features/edesk/comment_document_preview.dart';

class ProbePaste extends Intent {
  const ProbePaste();
}

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => S();
}

class S extends State<App> {
  final c = quill.QuillController.basic();
  final f = FocusNode();
  final scroll = ScrollController();
  String font = 'Roboto';
  int legacy = 0;
  late final void Function() stop;
  @override
  void initState() {
    super.initState();
    c.addListener(report);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    stop = listenForCommentPaste(
        accepts: () => f.hasFocus,
        onText: (text) {
          legacy++;
          final s = c.selection;
          c.replaceText(s.start, s.end - s.start, text,
              TextSelection.collapsed(offset: s.start + text.length));
          report();
        },
        onImage: (_) {});
  }

  void report() {
    web.document.body!.setAttribute(
        'data-probe',
        jsonEncode({
          'text': c.document.toPlainText(),
          'delta': c.document.toDelta().toJson(),
          'selection': c.selection.baseOffset,
          'legacy': legacy
        }));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      theme: ThemeData.dark(),
      localizationsDelegates: const [quill.FlutterQuillLocalizations.delegate],
      builder: (_, child) => WritingReviewScope(child: child!),
      home: Builder(
          builder: (ctx) => Scaffold(
              body: FocusScope(
                  autofocus: true,
                  child: Dialog(
                      child: SizedBox(
                          width: 1100,
                          height: 720,
                          child: Column(children: [
                            Row(children: [
                              TextButton(
                                  onPressed: () {
                                    c.formatSelection(quill.Attribute.bold);
                                    f.requestFocus();
                                  },
                                  child: const Text('Bold')),
                              SizedBox(
                                  width: 160,
                                  child: CommentFontPicker(
                                      value: font,
                                      controller: c,
                                      editorFocus: f,
                                      onChanged: (v) =>
                                          setState(() => font = v))),
                              TextButton(
                                  onPressed: () {
                                    final s = c.selection;
                                    c.replaceText(
                                        s.start,
                                        s.end - s.start,
                                        quill.BlockEmbed.image(
                                            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
                                        TextSelection.collapsed(
                                            offset: s.start + 1));
                                  },
                                  child: const Text('Image')),
                              TextButton(
                                  onPressed: () => showDialog<void>(
                                      context: ctx,
                                      builder: (_) => AlertDialog(
                                              content: SizedBox(
                                                  width: 600,
                                                  height: 350,
                                                  child: CommentDocumentPreview(
                                                      delta: c.document
                                                          .toDelta()
                                                          .toJson())),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                    child: const Text('Close'))
                                              ])),
                                  child: const Text('Preview')),
                            ]),
                            Expanded(
                                child: Shortcuts(
                                    shortcuts: const {
                                  SingleActivator(LogicalKeyboardKey.keyV,
                                      control: true): ProbePaste()
                                },
                                    child: Actions(
                                        actions: {
                                          ProbePaste:
                                              BrowserCommentPasteAction()
                                        },
                                        child: WritingReviewTarget(
                                            focusNode: f,
                                            readText: () =>
                                                c.document.toPlainText(),
                                            applyText: (_) {},
                                            child: commentEditor(
                                                controller: c,
                                                focusNode: f,
                                                fallback:
                                                    quill.QuillEditor.basic(
                                                        controller: c,
                                                        focusNode: f,
                                                        scrollController:
                                                            scroll)))))),
                            const TextField(
                                decoration:
                                    InputDecoration(labelText: 'Other field')),
                          ])))))));
}
