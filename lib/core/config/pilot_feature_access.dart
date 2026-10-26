/// Features available to every authenticated account. Backend authorization
/// and per-account data isolation are enforced independently.
class PilotFeatureAccess {
  PilotFeatureAccess._();
  // Retained only for this user's default archive destination.
  static const ownerEmail = 'rodrigozaparolli79@gmail.com';
  static bool allows({required String? uid, required String? email}) =>
      uid != null && uid.trim().isNotEmpty;
}
