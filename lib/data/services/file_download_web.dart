import 'dart:js_interop';
import 'dart:async';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser time to consume the URL before releasing the blob.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
