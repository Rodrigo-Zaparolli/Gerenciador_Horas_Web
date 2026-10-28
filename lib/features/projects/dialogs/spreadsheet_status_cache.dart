import 'package:flutter/foundation.dart';

/// Only calculations of the saved workbook belong in its durable snapshot.
Map<String, dynamic>? savedSpreadsheetStatus(
    Map<String, dynamic>? snapshot, Map<String, String> sheets) {
  if (snapshot == null ||
      snapshot['statusPreview'] is! Map ||
      snapshot['statusPreviewRevision'] != snapshot['revision'] ||
      snapshot['statusPreviewSheets'] is! Map ||
      !mapEquals(
          Map<String, dynamic>.from(snapshot['statusPreviewSheets'] as Map),
          sheets)) {
    return null;
  }
  return Map<String, dynamic>.from(snapshot['statusPreview'] as Map);
}

Map<String, dynamic> withSavedSpreadsheetStatus(Map<String, dynamic> snapshot,
        Map<String, String> sheets, Map<String, dynamic> status) =>
    {
      ...snapshot,
      'statusPreview': status,
      'statusPreviewRevision': snapshot['revision'],
      'statusPreviewSheets': Map<String, String>.from(sheets),
    };
