import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/platform/image_paste.dart';

/// Text and saved images share the same content viewport and scroll position.
class OrientationContent extends StatefulWidget {
  const OrientationContent({super.key, required this.controller, required this.images,
    required this.onPasteImage, required this.onRemoveImage, required this.onOpenImage});
  final TextEditingController controller;
  final List<String> images;
  final Future<void> Function(Uint8List) onPasteImage;
  final void Function(int) onRemoveImage;
  final void Function(String) onOpenImage;
  @override
  State<OrientationContent> createState() => _OrientationContentState();
}

class _OrientationContentState extends State<OrientationContent> {
  final focus = FocusNode();
  late final void Function() stopPaste;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(refresh);
    stopPaste = listenForImagePaste(accepts: () => mounted && focus.hasFocus,
      onImage: (bytes) async { await widget.onPasteImage(bytes); },
      onError: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível colar a imagem. Use Adicionar imagem.')));
      });
  }
  @override
  void didUpdateWidget(covariant OrientationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(refresh);
      widget.controller.addListener(refresh);
    }
  }
  void refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { widget.controller.removeListener(refresh); stopPaste(); focus.dispose(); super.dispose(); }

  Widget image(String value, int index) {
    Widget preview;
    try {
      final bytes = base64Decode(value.contains(',') ? value.substring(value.indexOf(',') + 1) : value);
      preview = Image.memory(bytes, key: ValueKey('orientation-content-image-$index'),
        fit: BoxFit.contain, errorBuilder: (_, error, stack) => const Text('Não foi possível exibir esta imagem.'));
    } catch (_) { preview = const Text('Não foi possível exibir esta imagem.'); }
    return Padding(padding: const EdgeInsets.only(top: 12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(onTap: () => widget.onOpenImage(value), child: preview),
        Align(alignment: Alignment.centerRight, child: IconButton(
          tooltip: 'Remover imagem ${index + 1}', onPressed: () => widget.onRemoveImage(index), icon: const Icon(Icons.delete_outline))),
      ]));
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: focus, child: Container(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(12)),
    child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.controller.text.trim().isEmpty && widget.images.isNotEmpty)
          for (var i = 0; i < widget.images.length; i++) image(widget.images[i], i),
        TextField(key: const ValueKey('orientation-description'), controller: widget.controller, maxLines: null, minLines: 5,
          style: const TextStyle(fontSize: 14, height: 1.55),
          decoration: const InputDecoration(hintText: 'Digite a orientação ou cole um print aqui...',
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false)),
        if (widget.controller.text.trim().isNotEmpty || widget.images.isEmpty)
          for (var i = 0; i < widget.images.length; i++) image(widget.images[i], i),
      ])),
  ));
}
