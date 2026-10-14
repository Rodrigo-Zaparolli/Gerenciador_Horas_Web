import 'dart:typed_data';
import 'image_paste_stub.dart'
    if (dart.library.js_interop) 'image_paste_web.dart' as platform;

void Function() listenForImagePaste(
        {required bool Function() accepts,
        required void Function(Uint8List) onImage,
        required void Function() onError}) =>
    platform.listenForImagePaste(
        accepts: accepts, onImage: onImage, onError: onError);
