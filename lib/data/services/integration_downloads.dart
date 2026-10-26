class IntegrationDownloads {
  const IntegrationDownloads(
      {required this.version,
      required this.updatePath,
      required this.completePath});
  final String version, updatePath, completePath;

  static IntegrationDownloads? fromJson(dynamic value) {
    if (value is! Map) return null;
    final version = value['version'];
    final update = value['updateUrl'];
    final complete = value['completeUrl'];
    if (version is! String || !RegExp(r'^[1-9][0-9]*$').hasMatch(version)) {
      return null;
    }
    bool valid(dynamic path) {
      if (path is! String ||
          !RegExp(r'^/downloads/[A-Za-z0-9._-]+\.zip$').hasMatch(path)) {
        return false;
      }
      return path.endsWith('-$version.zip') || path.endsWith('-v$version.zip');
    }

    if (!valid(update) || !valid(complete)) return null;
    return IntegrationDownloads(
        version: version, updatePath: update, completePath: complete);
  }
}
