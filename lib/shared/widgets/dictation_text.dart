import 'package:flutter/widgets.dart';

class DictationEdit {
  const DictationEdit(this.start, this.length, this.text);
  final int start, length;
  final String text;
  TextSelection get selection =>
      TextSelection.collapsed(offset: start + text.length);
}

DictationEdit planDictation(
    String current, TextSelection selection, String spoken,
    {int? maxOffset}) {
  final limit = (maxOffset ?? current.length).clamp(0, current.length);
  final start = selection.isValid ? selection.start.clamp(0, limit) : limit;
  final end = selection.isValid ? selection.end.clamp(start, limit) : start;
  var text = spoken.trim();
  if (text.isEmpty) return DictationEdit(start, 0, '');
  if (start > 0 &&
      !RegExp(r'[\s(\[{]').hasMatch(current[start - 1]) &&
      !RegExp(r'^[.,;:!?…)}\]]').hasMatch(text)) {
    text = ' $text';
  }
  if (end < current.length &&
      !RegExp(r'[\s.,;:!?…)}\]]').hasMatch(current[end])) {
    text = '$text ';
  }
  return DictationEdit(start, end - start, text);
}

void insertDictation(TextEditingController controller, String spoken) {
  final edit = planDictation(controller.text, controller.selection, spoken);
  if (edit.text.isEmpty) return;
  controller.value = TextEditingValue(
      text: controller.text
          .replaceRange(edit.start, edit.start + edit.length, edit.text),
      selection: edit.selection);
}
