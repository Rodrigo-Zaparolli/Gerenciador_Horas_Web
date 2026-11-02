import 'dart:convert';
import '../../../data/services/recoverable_draft.dart';
import 'workbook_value_validation.dart';

/// Drafts are local recovery data, never confirmation of an Excel write.
class SpreadsheetDraft {
  static String scope(String project, String reference, String worksheet) =>
      'spreadsheet.${jsonEncode([project, reference, worksheet])}';
  static Map<String, dynamic>? read(
          String? uid, String project, String reference, String worksheet) =>
      RecoverableDraft.read(uid, scope(project, reference, worksheet));
  static bool save(String? uid, String project, String reference,
          String worksheet, Map<String, dynamic> payload) =>
      RecoverableDraft.save(
          uid, scope(project, reference, worksheet), {'schema': 1, ...payload});
  static void clear(
          String? uid, String project, String reference, String worksheet) =>
      RecoverableDraft.clear(uid, scope(project, reference, worksheet));

  /// Reject the whole draft if any cell no longer has its original value,
  /// is calculated/protected, or contains an invalid typed value.
  static List<Map<String, dynamic>>? validatedChanges(
      Map<String, dynamic> draft,
      String revision,
      List<Map<String, dynamic>> fields) {
    if (draft['schema'] != 1 ||
        draft['revision'] != revision ||
        draft['changes'] is! List) {
      return null;
    }
    final changes = draft['changes'] as List;
    if (changes.length > 5000) return null;
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in changes) {
      if (raw is! Map) return null;
      final change = Map<String, dynamic>.from(raw);
      final key = '${change['sheet']}!${change['cell']}';
      final matches = fields
          .where((field) => '${field['sheet']}!${field['cell']}' == key)
          .toList();
      if (!seen.add(key) ||
          matches.length != 1 ||
          matches.single['readOnly'] == true ||
          !change.containsKey('before') ||
          change['before'] != matches.single['value'] ||
          !change.containsKey('value') ||
          validateWorkbookValue(matches.single, change['value']) != null) {
        return null;
      }
      result.add(change);
    }
    return result;
  }
}
