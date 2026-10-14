import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void Function() listenForCommentPaste({required bool Function() accepts,
  required void Function(String) onText, required void Function(Uint8List) onImage}) {
  final listener = ((web.Event raw) {
    if (!accepts()) return;
    final event = raw as web.ClipboardEvent;
    final text = event.clipboardData?.getData('text/plain') ?? '';
    if (text.isNotEmpty) {
      event.preventDefault(); event.stopImmediatePropagation();
      onText(text);
      return;
    }
    final files = event.clipboardData?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final image = files.item(i);
      if (image == null || !image.type.startsWith('image/') || image.size > 10 * 1024 * 1024) continue;
      event.preventDefault(); event.stopImmediatePropagation();
      image.arrayBuffer().toDart.then((data) {
        if (accepts()) onImage(Uint8List.view(data.toDart));
      }, onError: (_) {});
      return;
    }
  }).toJS;
  web.document.addEventListener('paste', listener, true.toJS);
  return () => web.document.removeEventListener('paste', listener, true.toJS);
}
