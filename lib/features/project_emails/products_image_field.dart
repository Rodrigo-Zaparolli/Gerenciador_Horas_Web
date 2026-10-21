import 'dart:async';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../core/platform/image_paste.dart';

class ProductsImageField extends StatefulWidget {
  const ProductsImageField(
      {super.key,
      required this.image,
      required this.onChanged,
      this.enabled = true,
      this.clipboardReader});
  final Uint8List? image;
  final ValueChanged<Uint8List?> onChanged;
  final bool enabled;
  final Future<Uint8List?> Function()? clipboardReader;
  @override
  State<ProductsImageField> createState() => _ProductsImageFieldState();
}

class _ProductsImageFieldState extends State<ProductsImageField> {
  final _focus = FocusNode();
  late final void Function() _stopPaste;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _stopPaste = listenForImagePaste(
        accepts: () => mounted && widget.enabled && _focus.hasFocus,
        onImage: (bytes) => unawaited(_accept(bytes)),
        onError: () {
          if (mounted) {
            setState(() => _error =
                'Não foi possível ler o print. Use Selecionar imagem.');
          }
        });
    _focus.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _accept(Uint8List bytes) async {
    if (!widget.enabled || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const FormatException();
      }
      Uint8List? result;
      for (final width in [1600, 1200, 900, 640]) {
        final codec = await ui.instantiateImageCodec(bytes,
            targetWidth: width, allowUpscaling: false);
        try {
          final frame = await codec.getNextFrame();
          try {
            final encoded =
                await frame.image.toByteData(format: ui.ImageByteFormat.png);
            result = encoded?.buffer.asUint8List();
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
        if (result != null && result.length <= 512 * 1024) break;
      }
      if (result == null || result.length > 512 * 1024) {
        throw const FormatException();
      }
      if (mounted && widget.enabled) widget.onChanged(result);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Use um print PNG ou JPG menor, com apenas os produtos da proposta.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _paste() async {
    _focus.requestFocus();
    try {
      final bytes = await (widget.clipboardReader?.call() ?? Pasteboard.image);
      if (!mounted || !widget.enabled) return;
      if (bytes == null) {
        setState(() => _error =
            'Copie o print, clique neste campo e pressione Ctrl + V. Também pode usar Selecionar imagem.');
      } else {
        await _accept(bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Clique neste campo e use Ctrl + V, ou Selecione a imagem.');
      }
    }
  }

  Future<void> _select() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg'],
          withData: true);
      if (!mounted || !widget.enabled || selection == null) return;
      final bytes = selection.files.single.bytes;
      if (bytes != null) await _accept(bytes);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Não foi possível selecionar. Tente colar o print com Ctrl + V.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
        focusNode: _focus,
        onKeyEvent: (_, event) {
          if (!kIsWeb &&
              widget.enabled &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyV &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed)) {
            unawaited(_paste());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
            onTap: widget.enabled ? _focus.requestFocus : null,
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color:
                            _focus.hasFocus ? scheme.primary : scheme.outline)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Produtos adquiridos',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (widget.image == null)
                        const Text(
                            'Clique aqui e cole o print da proposta com Ctrl + V.')
                      else
                        Image.memory(widget.image!,
                            key: const ValueKey('products-proposal-image'),
                            height: 180,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('Selecione novamente o print.')),
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        Text(_error!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        TextButton.icon(
                            onPressed:
                                widget.enabled && !_loading ? _paste : null,
                            icon: const Icon(Icons.content_paste),
                            label: const Text('Colar print')),
                        TextButton.icon(
                            onPressed:
                                widget.enabled && !_loading ? _select : null,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Selecionar imagem')),
                        if (widget.image != null)
                          TextButton(
                              onPressed: widget.enabled && !_loading
                                  ? () => widget.onChanged(null)
                                  : null,
                              child: const Text('Remover print')),
                      ]),
                      const Text(
                          'O print será incluído no corpo do e-mail e salvo neste projeto.',
                          style: TextStyle(fontSize: 12)),
                    ]))));
  }

  @override
  void dispose() {
    _stopPaste();
    _focus.removeListener(_redraw);
    _focus.dispose();
    super.dispose();
  }
}
