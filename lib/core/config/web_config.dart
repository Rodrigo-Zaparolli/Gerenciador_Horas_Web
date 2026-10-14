class WebConfig {
  static const storageEnabled = bool.fromEnvironment(
    'PROJECT_STORAGE_ENABLED',
    defaultValue: false,
  );
}
