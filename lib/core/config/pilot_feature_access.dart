/// Account allowlist for new features while they are being validated.
/// This controls presentation only. Any new write endpoint must independently
/// enforce the same restriction using verified Firebase token claims.
class PilotFeatureAccess {
  PilotFeatureAccess._();

  static const ownerEmail = 'rodrigozaparolli79@gmail.com';

  static bool allows({required String? uid, required String? email}) =>
      uid != null &&
      uid.trim().isNotEmpty &&
      email != null &&
      email.trim().toLowerCase() == ownerEmail;
}
