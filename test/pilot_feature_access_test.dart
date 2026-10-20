import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/config/pilot_feature_access.dart';

void main() {
  test('Pilot is exclusive to the authenticated designated account', () {
    expect(PilotFeatureAccess.allows(uid: 'owner', email: 'rodrigozaparolli79@gmail.com'), isTrue);
    expect(PilotFeatureAccess.allows(uid: 'owner', email: ' RodrigoZaparolli79@Gmail.com '), isTrue);
    expect(PilotFeatureAccess.allows(uid: null, email: PilotFeatureAccess.ownerEmail), isFalse);
    expect(PilotFeatureAccess.allows(uid: ' ', email: PilotFeatureAccess.ownerEmail), isFalse);
    expect(PilotFeatureAccess.allows(uid: 'another', email: 'another@gmail.com'), isFalse);
    expect(PilotFeatureAccess.allows(uid: 'owner', email: null), isFalse);
    expect(PilotFeatureAccess.allows(uid: 'owner', email: 'rodrigozaparolli79@gmail.com.invalid'), isFalse);
  });
}
