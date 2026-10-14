/// The specialized plugin tracker is exclusive to the designated Firebase account.
/// Project data remains protected by the existing per-user Firestore rules.
class PluginTrackingAccess {
  PluginTrackingAccess._();
  static const ownerEmail = 'rodrigozaparolli79@gmail.com';

  static bool allows({required String? uid, required String? email}) =>
      uid != null &&
      uid.trim().isNotEmpty &&
      email != null &&
      email.trim().toLowerCase() == ownerEmail;
}
