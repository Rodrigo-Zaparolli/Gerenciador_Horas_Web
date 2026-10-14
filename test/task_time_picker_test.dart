import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/tasks/task_time_picker.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('accepts 17:32 with a 12-hour browser preference ($brightness)',
        (tester) async {
      TimeOfDay? selected;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              selected = await showTaskTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 13, minute: 30),
              );
            },
            child: const Text('Edit'),
          ),
        )),
      ));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '17');
      await tester.enterText(fields.at(1), '32');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(selected, const TimeOfDay(hour: 17, minute: 32));
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  }
}
