import '../../core/platform/local_user_state.dart';

/// Recovery copy on this device, separate from cloud save and delivery.
class RecoverableDraft {
  static Map<String, dynamic>? read(String? uid, String feature) {
    final data = LocalUserState.read(uid, 'draft.$feature');
    final date = DateTime.tryParse(data?['savedAt']?.toString() ?? '');
    if (date == null || DateTime.now().difference(date).inDays > 30) {
      clear(uid, feature);
      return null;
    }
    return data;
  }

  static bool save(String? uid, String feature, Map<String, dynamic> data) =>
      LocalUserState.write(uid, 'draft.$feature',
          {...data, 'savedAt': DateTime.now().toIso8601String()});
  static void clear(String? uid, String feature) =>
      LocalUserState.remove(uid, 'draft.$feature');

  // Images are intentionally not copied to limited browser storage.
  static List<Map<String, dynamic>> textDelta(List<dynamic> delta) => [
        for (final operation in delta)
          if (operation is Map && operation['insert'] is String)
            Map<String, dynamic>.from(operation)
      ];
}
