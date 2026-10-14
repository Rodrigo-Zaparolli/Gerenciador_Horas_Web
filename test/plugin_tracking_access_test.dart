import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/config/plugin_tracking_access.dart';

void main() {
  test('acompanhamento exclusivo exige conta autenticada e email designado',
      () {
    expect(
        PluginTrackingAccess.allows(
            uid: 'owner', email: 'rodrigozaparolli79@gmail.com'),
        isTrue);
    expect(
        PluginTrackingAccess.allows(
            uid: 'owner', email: ' RODRIGOZAPAROLLI79@GMAIL.COM '),
        isTrue);
    for (final uid in [null, '', ' ']) {
      expect(
          PluginTrackingAccess.allows(
              uid: uid, email: PluginTrackingAccess.ownerEmail),
          isFalse);
    }
    for (final email in [
      null,
      '',
      'outro@gmail.com',
      'rodrigozaparolli79+teste@gmail.com',
      'rodrigozaparolli79@gmail.com.exemplo'
    ]) {
      expect(PluginTrackingAccess.allows(uid: 'other', email: email), isFalse);
    }
  });
}
