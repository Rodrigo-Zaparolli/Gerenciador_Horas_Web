import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_save_gate.dart';

void main() {
  test('testing, cancellation and failure never enable project saving', () {
    final gate = CommentSaveGate();
    expect(gate.canSave('text'), false);
    gate.receiveResult(content: 'text', sending: false, confirmed: true);
    expect(gate.canSave('text'), false);
    gate.receiveResult(content: 'text', sending: true, confirmed: false);
    expect(gate.canSave('text'), false);
  });
  test('confirmed content remains available for explicit save without resending', () {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'text and image', sending: true, confirmed: true);
    expect(gate.canSave('text and image'), true);
    expect(gate.alreadySent('text and image'), true);
    expect(gate.canSave('changed text'), false);
    gate.markSaved();
    expect(gate.canSave('text and image'), false);
    expect(gate.alreadySent('text and image'), true);
  });
  test('a new confirmed document can be saved after the previous one', () {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'first', sending: true, confirmed: true);
    gate.markSaved();
    gate.receiveResult(content: 'second', sending: true, confirmed: true);
    expect(gate.canSave('second'), true);
    expect(gate.canSave('first'), false);
  });
}
