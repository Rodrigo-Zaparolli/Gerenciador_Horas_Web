import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gerenciador_horas/data/services/update_service.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';

import 'main_navigation_screen.dart';
import '../shared/widgets/writing_review.dart';
import '../data/services/web_release_monitor.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';

class GerenciadorHorasApp extends StatelessWidget {
  const GerenciadorHorasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppVisualTheme>(
        valueListenable: AppAppearance.instance,
        builder: (context, mode, child) => MaterialApp(
              navigatorKey: appNavigatorKey,
              // ==========================================================
              // CONFIGURAÇÕES GERAIS
              // ==========================================================

              title: 'Gestão de Horas e Projetos',

              debugShowCheckedModeBanner: false,

              // ==========================================================
              // LOCALIZAÇÃO
              // ==========================================================

              locale: const Locale('pt', 'BR'),

              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],

              supportedLocales: const [
                Locale('pt', 'BR'),
                Locale('en', 'US'),
              ],

              // ==========================================================
              // TEMA
              // ==========================================================

              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode.mode,
              themeAnimationDuration: Duration.zero,
              builder: (context, child) => AppearanceScope(
                controller: AppAppearance.instance,
                child: WritingReviewScope(child: child ?? const SizedBox.shrink()),
              ),

              // ==========================================================
              // TELA INICIAL
              // ==========================================================
              //
              // O UpdateChecker executa a verificação de atualização
              // apenas uma vez após a interface estar carregada.
              // ==========================================================

              home: const _UpdateChecker(),
            ));
  }
}

// ================================================================
// VERIFICAÇÃO AUTOMÁTICA DE ATUALIZAÇÃO
// ================================================================

class _UpdateChecker extends StatefulWidget {
  const _UpdateChecker();

  @override
  State<_UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<_UpdateChecker> {
  bool _verificacaoExecutada = false;

  @override
  void initState() {
    super.initState();

    // Executa somente depois que o primeiro frame do MaterialApp
    // estiver completamente montado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarAtualizacao();
    });
  }

  Future<void> _verificarAtualizacao() async {
    // Evita executar a verificação mais de uma vez.
    if (_verificacaoExecutada) {
      return;
    }

    _verificacaoExecutada = true;

    if (!mounted) {
      return;
    }

    await verificarAtualizacaoAutomatica(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ========================================================
        // AGUARDANDO FIREBASE
        // ========================================================

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // ========================================================
        // ERRO
        // ========================================================

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro ao verificar autenticação:\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        // ========================================================
        // USUÁRIO LOGADO
        // ========================================================

        if (snapshot.hasData && snapshot.data != null) {
          return const WebReleaseMonitor(child: MainNavigationScreen());
        }

        // ========================================================
        // USUÁRIO NÃO LOGADO
        // ========================================================

        return LoginScreen(
          onLoginSuccess: () {
            // ====================================================
            // NÃO É NECESSÁRIO NAVEGAR MANUALMENTE.
            //
            // O FirebaseAuth.authStateChanges() detectará
            // automaticamente o login e reconstruirá esta tela.
            // ====================================================
          },
        );
      },
    );
  }
}
