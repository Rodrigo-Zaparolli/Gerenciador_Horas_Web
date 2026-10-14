import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';

import 'package:gerenciador_horas/app/app.dart';
import 'package:gerenciador_horas/firebase_options.dart';
import 'package:gerenciador_horas/core/platform/platform_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppAppearance.instance.restore();
  await _startApp();
}

Future<void> _startApp() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await initializePlatform();

    runApp(const GerenciadorHorasApp());
  } catch (_) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Não foi possível iniciar o aplicativo. Verifique sua conexão e tente novamente.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _startApp,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
