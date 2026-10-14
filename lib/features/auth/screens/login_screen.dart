import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/features/auth/widgets/auth_viewport.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/features/auth/screens/register_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ============================================================
  // LOGO
  // ============================================================

  static const String _logoHorizontal = 'assets/images/Logo_H.png';

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _animationController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty) {
      _showMessage(
        'Informe seu e-mail.',
        isError: true,
      );
      return;
    }

    if (password.isEmpty) {
      _showMessage(
        'Informe sua senha.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) {
        return;
      }

      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'O e-mail informado é inválido.';
          break;

        case 'user-not-found':
          message = 'Não encontramos uma conta com este e-mail.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message = 'E-mail ou senha incorretos.';
          break;

        case 'user-disabled':
          message = 'Esta conta foi desativada.';
          break;

        case 'too-many-requests':
          message =
              'Muitas tentativas. Aguarde alguns instantes e tente novamente.';
          break;

        case 'network-request-failed':
          message =
              'Não foi possível conectar ao servidor. Verifique sua internet.';
          break;

        default:
          message = e.message ?? 'Não foi possível realizar o login.';
      }

      if (mounted) {
        _showMessage(
          message,
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Ocorreu um erro inesperado ao realizar o login.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // RECUPERAR SENHA
  // ============================================================

  Future<void> _resetPassword() async {
    final String email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage(
        'Informe seu e-mail para recuperar a senha.',
        isError: true,
      );

      _emailFocusNode.requestFocus();
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Se o e-mail estiver cadastrado, enviaremos as instruções para recuperação da senha.',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'O e-mail informado é inválido.';
          break;

        default:
          message =
              e.message ?? 'Não foi possível enviar o e-mail de recuperação.';
      }

      _showMessage(
        message,
        isError: true,
      );
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Não foi possível solicitar a recuperação da senha.',
          isError: true,
        );
      }
    }
  }

  // ============================================================
  // ABRIR CADASTRO
  // ============================================================

  void _openRegisterScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          onRegisterSuccess: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // ============================================================
  // MENSAGEM
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: isError ? CoresApp.erro : CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ============================================================
  // LOGO HORIZONTAL
  // ============================================================

  Widget _buildHorizontalLogo({
    required double height,
  }) {
    return Image.asset(
      _logoHorizontal,
      fit: BoxFit.contain,
      height: height,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 30,
                color: CoresApp.primaria,
              ),
              const SizedBox(width: 10),
              Text(
                'Gerenciador de Horas e Projetos',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CHIP DE FUNCIONALIDADE
  // ============================================================

  Widget _buildFeatureChip({
    required IconData icon,
    required String text,
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 14,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 14 : 16,
            color: CoresApp.primaria,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CAMPO DE TEXTO
  // ============================================================

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        size: 20,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: CoresTelas.campoFormulario,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: CoresApp.primaria,
          width: 1.5,
        ),
      ),
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
      ),
      prefixIconColor: CoresApp.textoSecundario,
    );
  }

  // ============================================================
  // CARD DE LOGIN
  // ============================================================

  Widget _buildLoginCard({
    required bool smallHeight,
  }) {
    final double cardPadding = smallHeight ? 22 : 30;

    return Container(
      width: 430,
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: CoresApp.superficie,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CoresApp.borda,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 35,
            spreadRadius: 0,
            offset: const Offset(0, 15),
            color: Colors.black.withValues(alpha: 0.22),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ====================================================
          // TÍTULO
          // ====================================================

          Text(
            'Bem-vindo de volta!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: smallHeight ? 20 : 23,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Entre para continuar gerenciando seus projetos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: smallHeight ? 12 : 13,
            ),
          ),

          SizedBox(height: smallHeight ? 18 : 28),

          // ====================================================
          // E-MAIL
          // ====================================================

          TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) {
              _passwordFocusNode.requestFocus();
            },
            decoration: _inputDecoration(
              label: 'E-mail',
              icon: Icons.email_outlined,
            ),
          ),

          SizedBox(height: smallHeight ? 10 : 16),

          // ====================================================
          // SENHA
          // ====================================================

          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            enabled: !_isLoading,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              _handleLogin();
            },
            decoration: _inputDecoration(
              label: 'Senha',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
              ),
            ),
          ),

          SizedBox(height: smallHeight ? 3 : 10),

          // ====================================================
          // ESQUECI A SENHA
          // ====================================================

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _resetPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
              ),
              child: Text(
                'Esqueci minha senha',
                style: TextStyle(
                  color: CoresApp.primaria,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          SizedBox(height: smallHeight ? 7 : 12),

          // ====================================================
          // ENTRAR
          // ====================================================

          SizedBox(
            height: smallHeight ? 46 : 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.onPrimary,
                disabledBackgroundColor: CoresApp.primaria.withValues(alpha: 0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 19,
                        ),
                        SizedBox(width: 9),
                        Text(
                          'ENTRAR',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          SizedBox(height: smallHeight ? 12 : 22),

          // ====================================================
          // DIVISOR
          // ====================================================

          Row(
            children: [
              Expanded(
                child: Divider(
                  color: CoresApp.borda,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                child: Text(
                  'ou',
                  style: TextStyle(
                    color: CoresApp.textoFraco,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: CoresApp.borda,
                ),
              ),
            ],
          ),

          SizedBox(height: smallHeight ? 10 : 18),

          // ====================================================
          // CADASTRO
          // ====================================================

          SizedBox(
            height: smallHeight ? 42 : 48,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _openRegisterScreen,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.primary,
                side: BorderSide(
                  color: CoresApp.borda,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Criar nova conta',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Scaffold(
      backgroundColor: CoresApp.fundo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          AppAppearance.watch(context);
          final double width = constraints.maxWidth;
          final double height = constraints.maxHeight;

          final bool compact = width < 700;

          // Detecta telas com pouca altura.
          final bool smallHeight = height < 720;

          // Detecta telas muito pequenas.
          final bool verySmallHeight = height < 620;

          final double logoHeight = verySmallHeight
              ? 42
              : smallHeight
                  ? 52
                  : compact
                      ? 62
                      : 76;

          return Stack(
            children: [
              // ==================================================
              // FUNDO DECORATIVO
              // ==================================================

              Positioned(
                top: -180,
                left: -150,
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CoresApp.primaria.withValues(alpha: 0.06),
                  ),
                ),
              ),

              Positioned(
                bottom: -220,
                right: -160,
                child: Container(
                  width: 480,
                  height: 480,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CoresApp.destaque.withValues(alpha: 0.035),
                  ),
                ),
              ),

              // ==================================================
              // CONTEÚDO
              // ==================================================

              Positioned.fill(
                child: SafeArea(
                  child: AuthViewport(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 20 : 40,
                        vertical: verySmallHeight
                            ? 5
                            : smallHeight
                                ? 8
                                : 18,
                      ),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // ====================================
                              // LOGO
                              // ====================================

                              SizedBox(
                                height: logoHeight,
                                child: _buildHorizontalLogo(
                                  height: logoHeight,
                                ),
                              ),

                              SizedBox(
                                height: verySmallHeight
                                    ? 4
                                    : smallHeight
                                        ? 7
                                        : 14,
                              ),

                              // ====================================
                              // DESCRIÇÃO
                              // ====================================

                              if (!verySmallHeight)
                                Text(
                                  'Organize seu trabalho, acompanhe seus '
                                  'projetos e tenha controle total das suas horas.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: smallHeight ? 11 : 13,
                                    height: 1.35,
                                  ),
                                ),

                              SizedBox(
                                height: verySmallHeight
                                    ? 5
                                    : smallHeight
                                        ? 8
                                        : 14,
                              ),

                              // ====================================
                              // FUNCIONALIDADES
                              // ====================================

                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 7,
                                runSpacing: 6,
                                children: [
                                  _buildFeatureChip(
                                    icon: Icons.access_time_rounded,
                                    text: 'Horas',
                                    compact: compact || smallHeight,
                                  ),
                                  _buildFeatureChip(
                                    icon: Icons.folder_open_rounded,
                                    text: 'Projetos',
                                    compact: compact || smallHeight,
                                  ),
                                  _buildFeatureChip(
                                    icon: Icons.bar_chart_rounded,
                                    text: 'Métricas',
                                    compact: compact || smallHeight,
                                  ),
                                ],
                              ),

                              SizedBox(
                                height: verySmallHeight
                                    ? 7
                                    : smallHeight
                                        ? 10
                                        : 20,
                              ),

                              // ====================================
                              // CARD
                              // ====================================

                              _buildLoginCard(
                                smallHeight: smallHeight || verySmallHeight,
                              ),

                              SizedBox(
                                height: verySmallHeight
                                    ? 3
                                    : smallHeight
                                        ? 6
                                        : 12,
                              ),

                              // ====================================
                              // RODAPÉ
                              // ====================================

                              Text(
                                'Gestão de Horas e Projetos',
                                style: TextStyle(
                                  color: CoresApp.textoFraco,
                                  fontSize: verySmallHeight ? 8 : 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 8,
                right: 12,
                child: SafeArea(child: ThemeToggleButton()),
              ),
            ],
          );
        },
      ),
    );
  }
}
