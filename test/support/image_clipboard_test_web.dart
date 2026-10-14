import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void dispatchImagePaste(Uint8List bytes) {
  final clipboard = web.DataTransfer();
  clipboard.items.add(web.File(
      [bytes.toJS].toJS, 'print.png', web.FilePropertyBag(type: 'image/png')));
  web.document.dispatchEvent(web.ClipboardEvent(
      'paste',
      web.ClipboardEventInit(
          clipboardData: clipboard, bubbles: true, cancelable: true)));
}
