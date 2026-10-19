bool isActiveTrackingProject(Map<String, dynamic> project) =>
    project['status']?.toString().trim().toUpperCase() != 'TRAB_FIM';

/// Apply the project snapshot before any asynchronous comment/history reads.
/// Removing a tracking row never deletes the project or its history.
List<Map<String, dynamic>> retainActiveTrackingRows(
    List<Map<String, dynamic>> rows, Set<String> activeDocumentIds) =>
    rows.where((row) => activeDocumentIds.contains(row['docId'])).toList();
