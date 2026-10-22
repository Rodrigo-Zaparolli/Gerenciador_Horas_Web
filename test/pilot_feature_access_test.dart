import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/config/pilot_feature_access.dart';

void main() {
  test('Maiquel has all pilot features only with an authenticated account', () {
    for (final email in ['maiquel.elste@cyncly.com', ' MAIQUEL.ELSTE@CYNCLY.COM ']) {
      expect(PilotFeatureAccess.allows(uid: 'maiquel', email: email), isTrue);
      expect(PilotFeatureAccess.allows(uid: null, email: email), isFalse);
    }
    expect(PilotFeatureAccess.allows(uid: 'other', email: 'maiquel.elste@cyncly.com.invalid'), isFalse);
  });
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
