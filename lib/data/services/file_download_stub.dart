import 'dart:typed_data';

void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError('Browser downloads are only available on the web.');
}
