import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/assistant/beta_access.dart';
import 'package:gerenciador_horas/features/assistant/beta_assistant.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

void main() {
  test('BETA is enabled only for the pilot account', () {
    expect(
        BetaAccess.allows(uid: 'owner', email: 'rodrigozaparolli79@gmail.com'),
        isTrue);
    expect(
        BetaAccess.allows(uid: 'other', email: 'other@example.com'), isFalse);
    expect(BetaAccess.allows(uid: null, email: 'rodrigozaparolli79@gmail.com'),
        isFalse);
  });
  test('wake word is bounded and handles the approved greeting', () {
    for (final text in ['Beta', 'Olá, Beta', 'abrir Beta']) {
      expect(betaWake(text), isTrue);
    }
    expect(betaWake('enviar horas beta'), isFalse);
    expect(betaWake('o projeto beta'), isFalse);
  });
  test('changes to reviewed hours invalidate the snapshot, ordering does not',
      () {
    TimeLog log(String id) => TimeLog(
        id: id,
        targetId: '2265001/3',
        date: DateTime(2026, 11, 2),
        startTime: '09:00',
        endTime: '10:00',
        durationFormatted: '01:00',
        isRegistered: true,
        taskName: 'Implantação',
        description: 'Relatórios');
    final a = log('a'), b = log('b');
    final before = betaHoursFingerprint([a, b]);
    expect(betaHoursFingerprint([b, a]), before);
    a.endTime = '10:30';
    expect(betaHoursFingerprint([a, b]), isNot(before));
    a.endTime = '10:00';
    a.description = 'Outra descrição';
    expect(betaHoursFingerprint([a, b]), isNot(before));
  });
}
