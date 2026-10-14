import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Keeps the decoded image identity stable while Quill rebuilds on typing.
class CommentEditorImages {
  final _providers = <String, MemoryImage>{};

  static String normalized(String source) =>
      source.startsWith('data:') && source.contains(',')
          ? source.substring(source.indexOf(',') + 1)
          : source;

  static void retainPresent(quill.QuillController controller,
      List<String> images, List<String> ranges) {
    final present = controller.document
        .toDelta()
        .toJson()
        .map((op) => op['insert'])
        .whereType<Map>()
        .map((data) => data['image'])
        .whereType<String>()
        .map(normalized)
        .toSet();
    for (var i = images.length - 1; i >= 0; i--) {
      if (!present.contains(normalized(images[i]))) {
        images.removeAt(i);
        if (i < ranges.length) ranges.removeAt(i);
      }
    }
  }

  ImageProvider? provider(BuildContext context, String source) {
    final value = normalized(source);
    if (Uri.tryParse(value)?.hasScheme == true) return null;
    return _providers.putIfAbsent(
        value, () => MemoryImage(base64Decode(value)));
  }

  static void remove(quill.QuillController controller, String image) {
    final target = normalized(image);
    final offsets = <int>[];
    var offset = 0;
    for (final operation in controller.document.toDelta().toJson()) {
      final data = operation['insert'];
      if (data is Map &&
          data['image'] is String &&
          normalized(data['image'] as String) == target) {
        offsets.add(offset);
      }
      offset += data is String ? data.length : 1;
    }
    // Remove backwards so earlier offsets and surrounding formatting survive.
    for (final position in offsets.reversed) {
      final selection = controller.selection;
      int adjusted(int value) => value < 0
          ? 0
          : (value > position ? value - 1 : value)
              .clamp(0, controller.document.length - 2);
      controller.replaceText(
          position,
          1,
          '',
          TextSelection(
            baseOffset: adjusted(selection.baseOffset),
            extentOffset: adjusted(selection.extentOffset),
          ));
    }
  }
}
