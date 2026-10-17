/// A repair may only replace the exact old field, with this owner's full path.
Map<String, dynamic>? projectReferenceUpgrade(Map<String, dynamic> data,
    {required String uid,
    required String field,
    required String previous,
    required String resolved}) {
  if (!{'folderPath', 'excelLink'}.contains(field) ||
      previous == resolved ||
      data[field] != previous) {
    return null;
  }
  final uri = Uri.tryParse(resolved);
  if (uri == null ||
      uri.scheme !=
          (field == 'folderPath' ? 'desktop-folder' : 'desktop-file') ||
      uri.host != 'local' ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments.length != 3 ||
      uri.pathSegments.first != uid ||
      !RegExp(r'^[0-9a-f-]{36}$').hasMatch(uri.pathSegments[1])) {
    return null;
  }
  final path = uri.pathSegments.last;
  if (!RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)').hasMatch(path)) {
    return null;
  }
  return {field: resolved};
}
