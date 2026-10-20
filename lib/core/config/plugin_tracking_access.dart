import 'pilot_feature_access.dart';

/// The specialized plugin tracker is exclusive to the designated Firebase account.
/// Project data remains protected by the existing per-user Firestore rules.
class PluginTrackingAccess {
  PluginTrackingAccess._();
  static const ownerEmail = PilotFeatureAccess.ownerEmail;

  static bool allows({required String? uid, required String? email}) =>
      PilotFeatureAccess.allows(uid: uid, email: email);
}
