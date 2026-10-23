import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'client_contacts.dart';

void insertClientContact(quill.QuillController controller,
    TextSelection selection, ClientContact contact) {
  final start = selection.start.clamp(0, controller.document.length - 1);
  final end = selection.end.clamp(start, controller.document.length - 1);
  final text = contact.commentText;
  controller.replaceText(start, end - start, text,
      TextSelection.collapsed(offset: start + text.length));
}
