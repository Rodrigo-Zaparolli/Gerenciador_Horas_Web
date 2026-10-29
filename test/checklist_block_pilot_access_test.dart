import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/config/checklist_block_pilot_access.dart';
import 'package:gerenciador_horas/core/config/pilot_feature_access.dart';

void main() {
  test('new blocks are restricted to the authenticated owner', () {
    expect(
        ChecklistBlockPilotAccess.allows(
            uid: 'owner', email: PilotFeatureAccess.ownerEmail),
        isTrue);
    expect(
        ChecklistBlockPilotAccess.allows(
            uid: 'owner', email: '  RODRIGOZAPAROLLI79@GMAIL.COM  '),
        isTrue);
    for (final email in [
      null,
      '',
      'maiquel.elste@cyncly.com',
      'another@example.com'
    ]) {
      expect(ChecklistBlockPilotAccess.allows(uid: 'other', email: email),
          isFalse);
      expect(PilotFeatureAccess.allows(uid: 'other', email: email), isTrue);
    }
    expect(
        ChecklistBlockPilotAccess.allows(
            uid: null, email: PilotFeatureAccess.ownerEmail),
        isFalse);
    expect(
        ChecklistBlockPilotAccess.allows(
            uid: ' ', email: PilotFeatureAccess.ownerEmail),
        isFalse);
  });
}
