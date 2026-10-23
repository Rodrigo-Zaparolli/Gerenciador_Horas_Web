import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/native_local_files_service.dart';

void main() {
  test('only project-scoped name-only local links require recovery', () {
    for (final scheme in [
      'desktop-file',
      'desktop-folder',
      'browser-file',
      'browser-folder'
    ]) {
      final ref =
          '$scheme://local/owner/12345678-1234-1234-1234-123456789012/Documentos';
      expect(requiresLegacyProjectRecovery(ref, '2263800'), isTrue);
      expect(requiresLegacyProjectRecovery(ref, null), isFalse);
      expect(requiresLegacyProjectRecovery(ref, 'abc'), isFalse);
    }
    final full =
        'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/${Uri.encodeComponent(r'C:\Clientes\2263800 - Cliente\Documentos')}';
    expect(requiresLegacyProjectRecovery(full, '2263800'), isFalse);
    expect(requiresLegacyProjectRecovery(r'C:\Clientes\Documentos', '2263800'),
        isFalse);
    expect(
        requiresLegacyProjectRecovery(
            'https://example.com/Documentos', '2263800'),
        isFalse);
  });
}
