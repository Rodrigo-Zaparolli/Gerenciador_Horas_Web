import 'pilot_feature_access.dart';

/// The plugin tracker is available to every authenticated account.
/// Project data remains protected by the existing per-user Firestore rules.
class PluginTrackingAccess {
  PluginTrackingAccess._();
  static const ownerEmail = PilotFeatureAccess.ownerEmail;

  static bool allows({required String? uid, required String? email}) =>
      PilotFeatureAccess.allows(uid: uid, email: email);
}
