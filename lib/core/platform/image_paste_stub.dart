import 'dart:typed_data';

void Function() listenForImagePaste(
        {required bool Function() accepts,
        required void Function(Uint8List) onImage,
        required void Function() onError}) =>
    () {};
