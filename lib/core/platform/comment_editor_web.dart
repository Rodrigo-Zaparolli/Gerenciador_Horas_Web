import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:web/web.dart' as web;
import '../../features/dashboard/comentario/comment_native_document.dart';

@JS('gerenciadorNativeComment')
external JSAny? get _bridge;
@JS('gerenciadorNativeComment.create')
external JSPromise<JSObject> _create(web.HTMLElement host, JSString delta,
    JSFunction changed, JSFunction selected);
@JS('gerenciadorNativeComment.update')
external void _update(JSObject handle, JSString delta, int start, int end,
    JSString formats, bool readOnly);
@JS('gerenciadorNativeComment.focus')
external void _focus(JSObject handle);
@JS('gerenciadorNativeComment.destroy')
external void _destroy(JSObject handle);
Future<void>? _loadingBridge;
Future<void> _ensureBridge() {
  if (_bridge != null) return Future.value();
  return _loadingBridge ??= () async {
    final completed = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = Uri.parse(web.document.baseURI)
          .resolve('comment_native_editor.js?editor=keyboard-spelling-2')
          .toString();
    script.addEventListener(
        'load', ((web.Event _) => completed.complete()).toJS);
    script.addEventListener(
        'error',
        ((web.Event _) {
          _loadingBridge = null;
          completed.completeError(StateError('Editor indisponivel'));
        }).toJS);
    web.document.head!.append(script);
    await completed.future;
  }();
}

Widget commentEditor(
        {required quill.QuillController controller,
        required FocusNode focusNode,
        required Widget fallback}) =>
    _NativeCommentEditor(
        controller: controller, focus: focusNode, fallback: fallback);

class _NativeCommentEditor extends StatefulWidget {
  const _NativeCommentEditor(
      {required this.controller, required this.focus, required this.fallback});
  final quill.QuillController controller;
  final FocusNode focus;
  final Widget fallback;
  @override
  State<_NativeCommentEditor> createState() => _NativeState();
}

class _NativeState extends State<_NativeCommentEditor> {
  JSObject? handle;
  bool syncing = false, failed = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    widget.focus.addListener(focused);
  }

  void changed() {
    final current = handle;
    if (!mounted || syncing || current == null) return;
    final selected = widget.controller.selection;
    syncing = true;
    try {
      _update(
          current,
          jsonEncode(widget.controller.document.toDelta().toJson()).toJS,
          selected.start.clamp(0, widget.controller.document.length - 1),
          selected.end.clamp(0, widget.controller.document.length - 1),
          jsonEncode(widget.controller.getSelectionStyle().toJson()).toJS,
          widget.controller.readOnly);
    } finally {
      syncing = false;
    }
  }

  void focused() {
    if (widget.focus.hasFocus && handle != null) _focus(handle!);
  }

  Future<void> create(web.HTMLElement element) async {
    final color = Theme.of(context)
        .colorScheme
        .onSurface
        .toARGB32()
        .toRadixString(16)
        .substring(2);
    final hint = Theme.of(context)
        .colorScheme
        .onSurfaceVariant
        .toARGB32()
        .toRadixString(16)
        .substring(2);
    element.style.cssText =
        'box-sizing:border-box;width:100%;height:100%;overflow:hidden;color:#$color;--comment-placeholder:#$hint;';
    try {
      await _ensureBridge();
      if (!mounted) return;
      final created = await _create(
              element,
              jsonEncode(widget.controller.document.toDelta().toJson()).toJS,
              ((JSString raw, JSNumber start, JSNumber end) {
                if (!mounted || syncing || widget.controller.readOnly) return;
                syncing = true;
                try {
                  applyNativeCommentDocument(
                      widget.controller,
                      jsonDecode(raw.toDart) as List,
                      TextSelection(
                          baseOffset: start.toDartInt,
                          extentOffset: end.toDartInt));
                } finally {
                  syncing = false;
                }
              }).toJS,
              ((JSNumber start, JSNumber end) {
                if (!mounted || syncing) return;
                syncing = true;
                try {
                  widget.controller.updateSelection(
                      TextSelection(
                          baseOffset: start.toDartInt
                              .clamp(0, widget.controller.document.length - 1),
                          extentOffset: end.toDartInt
                              .clamp(0, widget.controller.document.length - 1)),
                      quill.ChangeSource.local);
                  widget.focus.requestFocus();
                } finally {
                  syncing = false;
                }
              }).toJS)
          .toDart;
      if (!mounted) {
        _destroy(created);
        return;
      }
      handle = created;
      changed();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => failed
      ? Column(children: [
          TextButton(
              onPressed: () => setState(() => failed = false),
              child: const Text(
                  'N\u00e3o foi poss\u00edvel iniciar o corretor no texto. Tentar novamente')),
          Expanded(child: widget.fallback)
        ])
      : Focus(
          // The DOM editor owns its keyboard. Flutter shortcuts must not
          // consume Space/Enter or dispatch them to a focused toolbar button.
          onKeyEvent: (_, event) => KeyEventResult.skipRemainingHandlers,
          focusNode: widget.focus,
          child: HtmlElementView.fromTagName(
              tagName: 'div',
              onElementCreated: (element) =>
                  create(element as web.HTMLElement)));
  @override
  void dispose() {
    widget.controller.removeListener(changed);
    widget.focus.removeListener(focused);
    if (handle != null) _destroy(handle!);
    super.dispose();
  }
}
