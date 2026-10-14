import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_percentage.dart';

void main() {
  test('Percentual opcional aceita limites e decimais com virgula', () {
    expect(parseCommentPercentage(''), isNull);
    for (final value in ['0', '100', '25,50', '0.25']) {
      expect(parseCommentPercentage(value),
          double.parse(value.replaceAll(',', '.')));
    }
    for (final value in ['-1', '101', 'NaN', 'Infinity', '1,2,3', '0.001']) {
      expect(() => parseCommentPercentage(value), throwsFormatException);
    }
  });
  testWidgets('Campo percentual permite digitar sem reconstruir o editor',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentPercentageField(
                controller: controller, enabled: true))));
    await tester.enterText(find.byType(TextField), '25,50');
    expect(parseCommentPercentage(controller.text), 25.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
