import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';

void main() {
  final formatter = HoraInputFormatter();
  TextEditingValue type(String input) {
    var value = TextEditingValue.empty;
    for (final character in input.split('')) {
      final text = '${value.text}$character';
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    }
    return value;
  }

  test('typing compact durations never drops digits after automatic colon', () {
    expect(type('2500').text, '25:00');
    expect(type('1000').text, '10:00');
    expect(type('2530').text, '25:30');
    expect(type('10000').text, '100:00');
    expect(type('999959').text, '9999:59');
  });

  test('explicit separator and pasted duration remain supported', () {
    expect(type('25:00').text, '25:00');
    expect(type('2:30').text, '2:30');
    expect(
      formatter.formatEditUpdate(TextEditingValue.empty,
          const TextEditingValue(text: '2500')).text,
      '25:00',
    );
  });

  test('replacing selected duration and deleting minute still work', () {
    expect(
      formatter.formatEditUpdate(const TextEditingValue(text: '10:00'),
          const TextEditingValue(text: '2500')).text,
      '25:00',
    );
    expect(
      formatter.formatEditUpdate(const TextEditingValue(text: '25:00'),
          const TextEditingValue(text: '25:0')).text,
      '25:0',
    );
  });
}
