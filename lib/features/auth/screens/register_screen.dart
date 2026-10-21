import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/auth/widgets/auth_viewport.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegisterSuccess;

  const RegisterScreen({
    super.key,
    required this.onRegisterSuccess,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // ============================================================
  // LOGO
  // ============================================================

  static const String _logoPath = 'assets/images/Logo_H.png';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();

    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  // ============================================================
  // CADASTRO
  // ============================================================

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();

    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (name.isEmpty) {
      _showMessage(
        'Informe seu nome completo.',
        isError: true,
      );
      _nameFocusNode.requestFocus();
      return;
    }

    if (email.isEmpty) {
      _showMessage(
        'Informe seu e-mail.',
        isError: true,
      );
      _emailFocusNode.requestFocus();
      return;
    }

    if (password.isEmpty) {
      _showMessage(
        'Informe uma senha.',
        isError: true,
      );
      _passwordFocusNode.requestFocus();
      return;
    }

    if (password.length < 6) {
      _showMessage(
        'A senha deve possuir pelo menos 6 caracteres.',
        isError: true,
      );
      _passwordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ========================================================
      // 1. CRIA USUÁRIO NO FIREBASE AUTH
      // ========================================================

      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // ========================================================
      // 2. SALVA INFORMAÇÕES DO USUÁRIO
      // ========================================================

      if (userCredential.user != null) {
        await userCredential.user!.updateDisplayName(name);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // ========================================================
      // 3. DESLOGA O USUÁRIO
      // ========================================================

      await FirebaseAuth.instance.signOut();

      if (!mounted) {
        return;
      }

      _showMessage(
        'Conta criada com sucesso! Faça login para continuar.',
      );

      // Pequeno intervalo para permitir que a mensagem seja vista.
      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (!mounted) {
        return;
      }

      widget.onRegisterSuccess();
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Erro ao criar conta.';

      switch (e.code) {
        case 'weak-password':
          errorMessage =
              'A senha fornecida é muito fraca. Use pelo menos 6 caracteres.';
          break;

        case 'email-already-in-use':
          errorMessage = 'Já existe uma conta cadastrada com este e-mail.';
          break;

        case 'invalid-email':
          errorMessage = 'O formato do e-mail informado é inválido.';
          break;

        case 'operation-not-allowed':
          errorMessage =
              'O cadastro por e-mail e senha não está habilitado no Firebase.';
          break;

        case 'network-request-failed':
          errorMessage =
              'Não foi possível conectar ao Firebase. Verifique sua conexão.';
          break;

        default:
          errorMessage = 'Erro (${e.code}): ${e.message ?? "Tente novamente."}';
      }

      if (mounted) {
        _showMessage(
          errorMessage,
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Erro inesperado ao criar conta. Verifique sua conexão.',
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
          duration: const Duration(seconds: 4),
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
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: 13,
      ),
      prefixIcon: Icon(
        icon,
        color: CoresApp.textoSecundario,
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: CoresApp.borda.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  // ============================================================
  // LOGO
  // ============================================================



  // ============================================================
  // CARD DE CADASTRO
  // ============================================================

  Widget _buildRegisterCard({
    required bool compact,
  }) {
    return Container(
      width: compact ? double.infinity : 430,
      padding: EdgeInsets.all(
        compact ? 24 : 30,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CoresApp.borda,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 35,
            spreadRadius: 0,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ====================================================
          // TÍTULO
          // ====================================================

          Text(
            'Criar nova conta',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            'Crie sua conta para começar a gerenciar '
            'suas horas e projetos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 13,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 28),

          // ====================================================
          // NOME
          // ====================================================

          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 14,
            ),
            onSubmitted: (_) {
              _emailFocusNode.requestFocus();
            },
            decoration: _inputDecoration(
              label: 'Nome completo',
              icon: Icons.person_outline_rounded,
            ),
          ),

          const SizedBox(height: 16),

          // ====================================================
          // E-MAIL
          // ====================================================

          TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 14,
            ),
            onSubmitted: (_) {
              _passwordFocusNode.requestFocus();
            },
            decoration: _inputDecoration(
              label: 'E-mail',
              icon: Icons.email_outlined,
            ),
          ),

          const SizedBox(height: 16),

          // ====================================================
          // SENHA
          // ====================================================

          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            enabled: !_isLoading,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 14,
            ),
            onSubmitted: (_) {
              if (!_isLoading) {
                _handleRegister();
              }
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
                  color: CoresApp.textoFraco,
                  size: 20,
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

          const SizedBox(height: 10),

          // ====================================================
          // INFORMAÇÃO DA SENHA
          // ====================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: CoresApp.textoFraco,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'A senha deve possuir pelo menos 6 caracteres.',
                  style: TextStyle(
                    color: CoresApp.textoFraco,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ====================================================
          // BOTÃO CADASTRAR
          // ====================================================

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                disabledBackgroundColor: CoresApp.primaria.withValues(alpha: 0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 19,
                          ),
                          SizedBox(width: 9),
                          Text(
                            'CRIAR CONTA',
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
          ),

          const SizedBox(height: 20),

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
                  'Conta segura',
                  style: TextStyle(
                    color: CoresApp.textoFraco,
                    fontSize: 11,
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

          const SizedBox(height: 16),

          // ====================================================
          // INFORMAÇÃO FIREBASE
          // ====================================================

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: CoresApp.sucesso,
              ),
              const SizedBox(width: 7),
              Flexible(
                  child: Text(
                'Seus dados são armazenados com segurança.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CoresApp.textoFraco, fontSize: 10.5),
              )),
            ],
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48,
        actions: const [ThemeToggleButton(), SizedBox(width: 8)],
        iconTheme: IconThemeData(
          color: CoresApp.primaria,
        ),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
          onPressed: _isLoading
              ? null
              : () {
                  Navigator.pop(context);
                },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          AppAppearance.watch(context);
          final double width = constraints.maxWidth;
          final double height = constraints.maxHeight;

          final bool compact = width < 700;

          // Espaço disponível depois da AppBar.
          final double availableHeight = height;

          // Ajusta o tamanho do conteúdo de acordo com a altura
          // disponível para evitar qualquer necessidade de rolagem.
          final bool smallHeight = availableHeight < 650;

          final double logoHeight = smallHeight
              ? 52
              : compact
                  ? 62
                  : 72;

          final double logoBottomSpace = smallHeight ? 8 : 14;

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
              // CONTEÚDO PRINCIPAL
              // ==================================================

              Positioned.fill(
                child: AuthViewport(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 20 : 40,
                      vertical: smallHeight ? 8 : 16,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ==========================================
                        // LOGO
                        // ==========================================

                        SizedBox(
                          height: logoHeight,
                          child: Image.asset(
                            _logoPath,
                            fit: BoxFit.contain,
                            errorBuilder: (
                              context,
                              error,
                              stackTrace,
                            ) {
                              return Text(
                                'Gestão de Horas e Projetos',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                        ),

                        SizedBox(
                          height: logoBottomSpace,
                        ),

                        // ==========================================
                        // LINHA DECORATIVA
                        // ==========================================

                        Container(
                          width: 42,
                          height: 3,
                          decoration: BoxDecoration(
                            color: CoresApp.primaria,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                        SizedBox(
                          height: smallHeight ? 10 : 16,
                        ),

                        // ==========================================
                        // CARD
                        // ==========================================

                        _buildRegisterCard(compact: compact),

                        SizedBox(
                          height: smallHeight ? 6 : 10,
                        ),

                        // ==========================================
                        // RODAPÉ
                        // ==========================================

                        Text(
                          'Gestão de Horas e Projetos',
                          style: TextStyle(
                            color: CoresApp.textoFraco,
                            fontSize: smallHeight ? 9 : 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
