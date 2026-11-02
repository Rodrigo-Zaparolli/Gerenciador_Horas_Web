import '../../core/config/pilot_feature_access.dart';

class BetaAccess {
  static bool allows({required String? uid, required String? email}) =>
      uid != null &&
      uid.isNotEmpty &&
      email?.trim().toLowerCase() == PilotFeatureAccess.ownerEmail;
}
