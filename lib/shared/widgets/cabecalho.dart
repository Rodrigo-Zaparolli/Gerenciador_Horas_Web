import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:convert';
import 'adaptive_header_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';
import 'package:gerenciador_horas/features/backup/backup_dialog.dart';
import 'package:gerenciador_horas/features/edesk/edesk_history_dialog.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';

class Cabecalho extends StatefulWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String userName;

  const Cabecalho({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.userName,
  });

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  State<Cabecalho> createState() => _CabecalhoState();
}

class _CabecalhoState extends State<Cabecalho> {
  final UserCache _cache = UserCache();

  final EdeskCredentialsService _edeskCredentials = EdeskCredentialsService();

  late final TextEditingController _searchController;

  bool _carregandoFoto = false;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(
      text: widget.searchQuery,
    );

    if (!_cache.carregado) {
      _carregarFotoDoFirestore();
    }
  }

  @override
  void didUpdateWidget(covariant Cabecalho oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchQuery != widget.searchQuery &&
        _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;

      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // FOTO / USUÁRIO
  // ============================================================

  Future<void> _carregarFotoDoFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _cache.carregado = true;
        return;
      }

      _cache.userName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? widget.userName;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();

      if (data != null) {
        final fotoBase64 = data['photoBase64'];

        if (fotoBase64 is String && fotoBase64.isNotEmpty) {
          try {
            final bytes = base64Decode(fotoBase64);

            _cache.fotoPerfilProvider = MemoryImage(bytes);
          } catch (_) {
            _cache.fotoPerfilProvider = null;
          }
        }
      }

      _cache.carregado = true;

      if (mounted && context.mounted) {
        setState(() {});
      }
    } catch (_) {
      _cache.carregado = true;
    }
  }

  Future<void> _alterarFotoPerfil() async {
    if (_carregandoFoto) return;

    try {
      final picker = ImagePicker();

      final XFile? imagem = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 70,
      );

      if (imagem == null) return;

      setState(() {
        _carregandoFoto = true;
      });

      final bytes = await imagem.readAsBytes();
      final base64Imagem = base64Encode(bytes);

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoBase64': base64Imagem,
        },
        SetOptions(merge: true),
      );

      _cache.fotoPerfilProvider = MemoryImage(bytes);
      _cache.carregado = true;

      if (mounted && context.mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil atualizada.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível alterar a foto: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted && context.mounted) {
        setState(() {
          _carregandoFoto = false;
        });
      }
    }
  }

  String _getUserName() {
    final cacheName = _cache.userName?.trim();

    if (cacheName != null && cacheName.isNotEmpty) {
      return cacheName;
    }

    final user = FirebaseAuth.instance.currentUser;

    final displayName = user?.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    final widgetName = widget.userName.trim();

    if (widgetName.isNotEmpty) {
      return widgetName;
    }

    return 'Usuário';
  }

  // ============================================================
  // CREDENCIAIS E-DESK
  // ============================================================

  Future<void> _abrirCredenciaisEdesk() async {
    final emailController = TextEditingController();
    final senhaController = TextEditingController();

    bool mostrarSenha = false;
    bool salvando = false;
    bool possuiCredenciais = false;
    String? erroCarregamento;

    try {
      final dados = await _edeskCredentials.ler();

      if (dados != null) {
        emailController.text = dados['email'] ?? '';
        senhaController.text = dados['senha'] ?? '';
        possuiCredenciais = true;
      }
    } catch (_) {
      erroCarregamento = 'Não foi possível recuperar as credenciais. Verifique a conexão e reabra esta janela.';
    }

    if (!mounted || !context.mounted) {
      emailController.dispose();
      senhaController.dispose();
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: CoresApp.primaria,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Credenciais E-Desk',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Configure o acesso que será utilizado '
                        'automaticamente nas ações do E-Desk.',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (erroCarregamento != null) Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(erroCarregamento, style: TextStyle(color: CoresApp.erro)),
                    ),

                    // ==================================================
                    // E-MAIL
                    // ==================================================

                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'E-mail do E-Desk',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: CoresApp.textoSecundario,
                        ),
                        filled: true,
                        fillColor: CoresApp.superficieEscura,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ==================================================
                    // SENHA
                    // ==================================================

                    TextField(
                      controller: senhaController,
                      obscureText: !mostrarSenha,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Senha do E-Desk',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        prefixIcon: Icon(
                          Icons.password_rounded,
                          color: CoresApp.textoSecundario,
                        ),
                        suffixIcon: IconButton(
                          tooltip:
                              mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: () {
                            setDialogState(() {
                              mostrarSenha = !mostrarSenha;
                            });
                          },
                          icon: Icon(
                            mostrarSenha
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                        filled: true,
                        fillColor: CoresApp.superficieEscura,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // AVISO
                    // ==================================================

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.security_rounded,
                            color: Colors.blueAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'As credenciais serão salvas na sua conta do app no Firebase '
                              'e carregadas ao entrar em outro computador. '
                              'Uma cópia local permite reutilizar as credenciais neste navegador.',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (possuiCredenciais) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Credenciais cadastradas',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                // ======================================================
                // REMOVER
                // ======================================================

                if (possuiCredenciais)
                  TextButton.icon(
                    onPressed: salvando
                        ? null
                        : () async {
                            try {
                              setDialogState(() {
                                salvando = true;
                              });

                              await _edeskCredentials.apagar();

                              emailController.clear();
                              senhaController.clear();

                              setDialogState(() {
                                salvando = false;
                                possuiCredenciais = false;
                              });

                              if (mounted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Credenciais do E-Desk removidas.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                salvando = false;
                              });

                              if (mounted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao remover credenciais: $e',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: CoresApp.erro,
                    ),
                    label: Text(
                      'Remover',
                      style: TextStyle(
                        color: CoresApp.erro,
                      ),
                    ),
                  ),

                // ======================================================
                // CANCELAR
                // ======================================================

                TextButton(
                  onPressed: salvando
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),

                // ======================================================
                // SALVAR
                // ======================================================

                ElevatedButton.icon(
                  onPressed: salvando
                      ? null
                      : () async {
                          final email = emailController.text.trim();

                          final senha = senhaController.text;

                          if (email.isEmpty) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Informe o e-mail do E-Desk.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (senha.isEmpty) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Informe a senha do E-Desk.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            salvando = true;
                          });

                          try {
                            await _edeskCredentials.salvar(
                              email: email,
                              senha: senha,
                            );

                            if (!dialogContext.mounted || !context.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();

                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Credenciais do E-Desk salvas na sua conta do app.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              salvando = false;
                            });

                            if (!dialogContext.mounted || !context.mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao salvar credenciais: $e',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save_rounded,
                          size: 17,
                        ),
                  label: Text(
                    salvando ? 'Salvando...' : 'Salvar',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
    senhaController.dispose();
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _confirmarLogout() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Sair da conta',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente sair da sua conta?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
              ),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (resultado == true) {
      await _realizarLogout();
    }
  }

  Future<void> _realizarLogout() async {
    try {
      await FirebaseAuth.instance.signOut();

      _cache.carregado = false;
      _cache.userName = '';
      _cache.fotoPerfilProvider = null;
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao sair da conta: $e',
            ),
          ),
        );
      }
    }
  }

  // ============================================================
  // MENU DO USUÁRIO
  // ============================================================

  Future<void> _abrirMenuUsuario() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      backgroundColor: Colors.transparent,
      builder: (context) {
        AppAppearance.watch(context);
        return Material(
          color: CoresApp.superficie,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            side: BorderSide(
              color: AppPalette.text.withValues(alpha: 0.08),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ==================================================
                    // USUÁRIO
                    // ==================================================

                    Row(
                      children: [
                        _buildProfileAvatar(size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getUserName(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Conta conectada',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Divider(
                      color: CoresApp.borda,
                      height: 1,
                    ),

                    const SizedBox(height: 8),

                    // ==================================================
                    // CREDENCIAIS E-DESK
                    // ==================================================

                    if (kIsWeb)
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: const Text('Estado da integração E-Desk'),
                        onTap: () => Navigator.of(context).pop('integration'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Backup e restauração'),
                      onTap: () => Navigator.of(context).pop('backup'),
                    ),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Histórico de envios ao E-Desk'),
                        onTap: () => Navigator.of(context).pop('history'),
                      ),
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: Colors.blueAccent,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Credenciais E-Desk',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Configurar acesso automático',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                      trailing: FutureBuilder<bool>(
                        future: _edeskCredentials.possuiCredenciais(),
                        builder: (context, snapshot) {
                          AppAppearance.watch(context);
                          if (snapshot.data == true) {
                            return const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 19,
                            );
                          }

                          return Icon(
                            Icons.chevron_right_rounded,
                            color: CoresApp.textoSecundario,
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.of(context).pop('edesk');
                      },
                    ),

                    const SizedBox(height: 4),

                    // ==================================================
                    // FOTO
                    // ==================================================

                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.photo_camera_outlined,
                          color: CoresApp.primaria,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Alterar foto de perfil',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Escolher uma nova imagem',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop('foto');
                      },
                    ),

                    const SizedBox(height: 4),

                    // ==================================================
                    // LOGOUT
                    // ==================================================

                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CoresApp.erro.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.logout_rounded,
                          color: CoresApp.erro,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Sair da conta',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Encerrar a sessão atual',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop('logout');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || !context.mounted) return;

    if (escolha == 'backup') {
      await showBackupDialog(context);
    } else if (escolha == 'history') {
      await showEdeskHistory(context);
    } else if (escolha == 'integration') {
      await showIntegrationStatus(context);
    } else if (escolha == 'edesk') {
      await _abrirCredenciaisEdesk();
    } else if (escolha == 'foto') {
      await _alterarFotoPerfil();
    } else if (escolha == 'logout') {
      await _confirmarLogout();
    }
  }

  // ============================================================
  // AVATAR
  // ============================================================

  Widget _buildProfileAvatar({
    double size = 38,
  }) {
    final foto = _cache.fotoPerfilProvider;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CoresApp.borda,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: foto != null
            ? Image(
                image: foto,
                fit: BoxFit.cover,
              )
            : Container(
                color: CoresApp.primaria.withValues(alpha: 0.18),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: CoresApp.primaria,
                  size: size * 0.52,
                ),
              ),
      ),
    );
  }

  // ============================================================
  // NAVEGAÇÃO
  // ============================================================

  final List<_MenuItemData> _menuItems = const [
    _MenuItemData(
      index: 0,
      label: 'Projetos',
      icon: Icons.dashboard_outlined,
    ),
    _MenuItemData(
      index: 1,
      label: 'Cadastro de Trabalhos',
      icon: Icons.work_outline_rounded,
    ),
    _MenuItemData(
      index: 2,
      label: 'Métricas',
      icon: Icons.analytics_outlined,
    ),
    _MenuItemData(
      index: 3,
      label: 'Projetos Finalizados',
      icon: Icons.task_alt_rounded,
    ),
    _MenuItemData(
      index: 4,
      label: 'Orientações',
      icon: Icons.menu_book_outlined,
    ),
    _MenuItemData(
      index: 5,
      label: 'Tarefas',
      icon: Icons.playlist_add_check_rounded,
    ),
    _MenuItemData(
      index: 6,
      label: 'Check List',
      icon: Icons.checklist_rounded,
    ),
    _MenuItemData(
      index: 7,
      label: 'Solicitações',
      icon: Icons.markunread_mailbox_outlined,
    ),
  ];

  Widget _buildTopTabItem(
    _MenuItemData item,
    bool compact,
  ) {
    final selecionado = widget.selectedIndex == item.index;

    return Tooltip(
      message: item.label,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          widget.onSelectTab(item.index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selecionado
                ? CoresApp.primaria.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 20,
                color:
                    selecionado ? CoresApp.primaria : CoresApp.textoSecundario,
              ),
              ...[
                const SizedBox(height: 3),
                Text(
                  compact ? item.shortLabel : item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selecionado
                        ? CoresApp.textoPrincipal
                        : CoresApp.textoSecundario,
                    fontSize: compact ? 10.5 : 11,
                    fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: selecionado ? 20 : 0,
                decoration: BoxDecoration(
                  color: CoresApp.primaria,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // ============================================================
  // MENU COMPACTO
  // ============================================================

  Future<void> _abrirMenuNavegacao() async {
    final escolha = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        AppAppearance.watch(context);
        return Container(
          decoration: BoxDecoration(
            color: CoresApp.superficie,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                14,
                12,
                14,
                18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Navegação',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._menuItems.map(
                    (item) {
                      final selecionado = widget.selectedIndex == item.index;

                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: selecionado
                            ? CoresApp.primaria.withValues(alpha: 0.12)
                            : Colors.transparent,
                        leading: Icon(
                          item.icon,
                          color: selecionado
                              ? CoresApp.primaria
                              : CoresApp.textoSecundario,
                        ),
                        title: Text(
                          item.label,
                          style: TextStyle(
                            color: selecionado
                                ? CoresApp.textoPrincipal
                                : CoresApp.textoSecundario,
                            fontWeight:
                                selecionado ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: selecionado
                            ? Icon(
                                Icons.check_rounded,
                                color: CoresApp.primaria,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).pop(item.index);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || escolha == null) return;

    widget.onSelectTab(escolha);
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final width = MediaQuery.of(context).size.width;

    final bool isVeryCompact = width < 850;
    final bool isCompact = width < 1150;

    // ============================================================
    // DIMENSÕES RESPONSIVAS
    // ============================================================

    final double logoWidth = isVeryCompact
        ? (width < 400 ? 80 : 96)
        : isCompact
            ? 150
            : 190;

    final double searchWidth = isCompact ? 125 : 185;

    final bool mostrarNomeUsuario = width >= 980;

    final double nomeUsuarioWidth = width >= 1200 ? 145 : 82;

    final userName = _getUserName();

    return Material(
      color: AppPalette.surface,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: AppPalette.surface,
          border: Border(
            bottom: BorderSide(
              color: AppPalette.border,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              // ==================================================
              // LOGO
              // ==================================================

              Padding(
                padding: EdgeInsets.only(
                  left: isVeryCompact ? 8 : 12,
                  right: isVeryCompact ? 6 : 10,
                ),
                child: SizedBox(
                  width: logoWidth,
                  height: 54,
                  child: Semantics(
                    label: 'Gerenciador de Horas',
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: isVeryCompact ? 28 : 34,
                            color: AppPalette.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isVeryCompact ? 'GH' : 'Gerenciador\nde Horas',
                            maxLines: 2,
                            style: TextStyle(
                              color: AppPalette.text,
                              fontSize: isCompact ? 13 : 16,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(
                width: 1,
                height: 30,
                color: CoresApp.bordaSuave,
              ),

              const SizedBox(width: 4),

              // ==================================================
              // NAVEGAÇÃO
              // ==================================================

              if (isVeryCompact)
                IconButton(
                  tooltip: 'Navegação',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 42,
                    minHeight: 42,
                  ),
                  onPressed: _abrirMenuNavegacao,
                  icon: Icon(
                    Icons.menu_rounded,
                    color: CoresApp.textoPrincipal,
                  ),
                )
              else
                Expanded(
                  child: AdaptiveHeaderNavigation(
                    labels: _menuItems.map((item) => item.label).toList(),
                    shortLabels: _menuItems.map((item) => item.shortLabel).toList(),
                    itemBuilder: (index, compact) =>
                        _buildTopTabItem(_menuItems[index], compact),
                  ),
                ),

              if (!isVeryCompact) const SizedBox(width: 6),

              // ==================================================
              // BUSCA
              // ==================================================

              if (!isVeryCompact)
                Flexible(
                  flex: 0,
                  child: SizedBox(
                    width: searchWidth,
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        widget.onSearchChanged(value);
                        setState(() {});
                      },
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar...',
                        hintStyle: TextStyle(
                          color: CoresApp.textoFraco,
                          fontSize: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: CoresApp.textoSecundario,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Limpar',
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _searchController.clear();
                                  widget.onSearchChanged('');
                                  setState(() {});
                                },
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: CoresApp.textoSecundario,
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: CoresApp.superficieEscura,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 6),

              Container(
                width: 1,
                height: 30,
                color: CoresApp.bordaSuave,
              ),

              // ==================================================
              // PERFIL
              // ==================================================

              const SizedBox(width: 6),

              const ThemeToggleButton(),

              if (kIsWeb) const EdeskConnectionButton(),

              if (isVeryCompact)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _abrirMenuUsuario,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Stack(
                      children: [
                        _buildProfileAvatar(size: 38),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: CoresApp.sucesso,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: CoresApp.fundo,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _abrirMenuUsuario,
                  child: Container(
                    height: 42,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 5 : 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.superficie,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CoresApp.bordaSuave,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            _buildProfileAvatar(
                              size: isCompact ? 34 : 36,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: CoresApp.sucesso,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: CoresApp.fundo,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (mostrarNomeUsuario) ...[
                          SizedBox(
                            width: width >= 1200 ? 9 : 6,
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: nomeUsuarioWidth,
                              minWidth: 0,
                            ),
                            child: Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: CoresApp.textoSecundario,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// MODELO INTERNO DOS ITENS DO MENU
// ================================================================

class _MenuItemData {
  final int index;
  final String label;
  final IconData icon;
  String get shortLabel => switch (index) {
    1 => 'Trabalhos',
    3 => 'Finalizados',
    6 => 'Checklist',
    _ => label,
  };

  const _MenuItemData({
    required this.index,
    required this.label,
    required this.icon,
  });
}
