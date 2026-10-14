import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart' as extensions;
import '../dashboard/comentario/comment_editor_images.dart';

/// A detached copy of the current editor; no history or image fallback.
class CommentDocumentPreview extends StatefulWidget {
  const CommentDocumentPreview({super.key, required this.delta});
  final List<dynamic> delta;
  @override
  State<CommentDocumentPreview> createState() => _CommentDocumentPreviewState();
}
class _CommentDocumentPreviewState extends State<CommentDocumentPreview> {
  late final quill.QuillController _controller;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _images = CommentEditorImages();
  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: quill.Document.fromJson(jsonDecode(jsonEncode(widget.delta)) as List<dynamic>),
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
  }
  @override
  void dispose() { _controller.dispose(); _focus.dispose(); _scroll.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final config = extensions.QuillEditorImageEmbedConfig(imageProviderBuilder: _images.provider);
    return Localizations.override(context: context, delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: quill.QuillEditor.basic(controller: _controller, focusNode: _focus, scrollController: _scroll,
      config: quill.QuillEditorConfig(
        padding: const EdgeInsets.all(8), scrollable: false, autoFocus: false,
        embedBuilders: kIsWeb ? extensions.FlutterQuillEmbeds.editorWebBuilders(imageEmbedConfig: config)
          : extensions.FlutterQuillEmbeds.editorBuilders(imageEmbedConfig: config),
      )));
  }
}
