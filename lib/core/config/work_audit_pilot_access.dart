import 'pilot_feature_access.dart';

class WorkAuditPilotAccess {
  WorkAuditPilotAccess._();
  static bool allows({required String? uid, required String? email}) =>
      uid != null &&
      uid.trim().isNotEmpty &&
      email?.trim().toLowerCase() == PilotFeatureAccess.ownerEmail;
}
