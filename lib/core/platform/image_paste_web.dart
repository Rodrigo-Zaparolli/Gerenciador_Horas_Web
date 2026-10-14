import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void Function() listenForImagePaste(
    {required bool Function() accepts,
    required void Function(Uint8List) onImage,
    required void Function() onError}) {
  final listener = ((web.Event raw) {
    if (!accepts()) return;
    final event = raw as web.ClipboardEvent;
    final files = event.clipboardData?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      event.preventDefault();
      if (file.size > 10 * 1024 * 1024) {
        onError();
        return;
      }
      file.arrayBuffer().toDart.then((buffer) {
        if (accepts()) onImage(Uint8List.view(buffer.toDart));
      }, onError: (_) {
        onError();
      });
      return;
    }
  }).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}
