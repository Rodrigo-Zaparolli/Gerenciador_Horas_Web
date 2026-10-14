import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

Future<void> initializePlatform() async {
  if (!Platform.isWindows) {
    return;
  }

  final appData = await getApplicationSupportDirectory();

  final pastaEdesk = Directory(
    '${appData.path}${Platform.pathSeparator}EdeskWebView',
  );

  await pastaEdesk.create(recursive: true);

  await WebviewController.initializeEnvironment(
    userDataPath: pastaEdesk.path,
  );
}
