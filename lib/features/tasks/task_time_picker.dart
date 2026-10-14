import 'package:flutter/material.dart';

/// Uses the same 24-hour convention as stored task times, regardless of the
/// browser's locale. The picker inherits the application's current theme.
Future<TimeOfDay?> showTaskTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: TimePickerEntryMode.input,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}
