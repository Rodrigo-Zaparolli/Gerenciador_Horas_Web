Future<bool> edeskExtensionAvailable() async => false;
Future<Map<String, dynamic>> edeskExtensionCall(String path,
        {Map<String, dynamic>? body, String? uid}) async =>
    throw UnsupportedError('A extensão requer o navegador.');
