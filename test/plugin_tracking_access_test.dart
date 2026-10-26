import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/config/plugin_tracking_access.dart';

void main() {
  test('All authenticated accounts are allowed and login remains required', () {
    for (final email in [
      null,
      '',
      'another@example.com',
      'maiquel.elste@cyncly.com'
    ]) {
      expect(PluginTrackingAccess.allows(uid: 'any-account', email: email),
          isTrue);
      for (final uid in [null, '', ' ']) {
        expect(PluginTrackingAccess.allows(uid: uid, email: email), isFalse);
      }
    }
  });
}
