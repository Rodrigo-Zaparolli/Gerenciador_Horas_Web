import 'pilot_feature_access.dart';

/// UI rollout only; existing authentication and data permissions stay in place.
class ChecklistBlockPilotAccess {
  ChecklistBlockPilotAccess._();
  static bool allows({required String? uid, required String? email}) =>
      uid != null &&
      uid.trim().isNotEmpty &&
      email?.trim().toLowerCase() == PilotFeatureAccess.ownerEmail;
}
