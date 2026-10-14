import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class OrientacaoModel {
  final String id;

  String titulo;

  final TextEditingController controller;

  bool expandido;
  bool editandoTitulo;

  late TextEditingController tituloController;

  Offset posicao;

  double largura;
  double alturaTexto;

  List<String> imagens;

  OrientacaoModel({
    required this.id,
    required this.titulo,
    required String textoInicial,
    this.expandido = true,
    this.editandoTitulo = false,
    this.posicao = const Offset(50, 50),
    this.largura = 600.0,
    this.alturaTexto = 500.0,
    List<String>? imagens,
  })  : controller = TextEditingController(text: textoInicial),
        tituloController = TextEditingController(text: titulo),
        imagens = List<String>.from(imagens ?? []);

  Map<String, dynamic> toJson() {
    return {
      'titulo': titulo,
      'texto': controller.text,
      'expandido': expandido,
      'posX': posicao.dx,
      'posY': posicao.dy,
      'largura': largura,
      'alturaTexto': alturaTexto,
      'imagens': List<String>.from(imagens),
    };
  }

  void dispose() {
    controller.dispose();
    tituloController.dispose();
  }
}

class OrientacaoScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const OrientacaoScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required String userName,
  });

  @override
  State<OrientacaoScreen> createState() => _OrientacaoScreenState();
}

class _OrientacaoScreenState extends State<OrientacaoScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  bool _isLoading = true;
  String? _erroCarregamento;

  final List<OrientacaoModel> _orientacoes = [];

  String _filtroPesquisa = '';

  final TextEditingController _pesquisaController = TextEditingController();

  String? _cardComFoco;

  bool _colandoImagem = false;

  final Map<String, Timer> _timersSalvamento = {};

  final Set<String> _salvandoIds = {};

  String? _ultimoSalvoId;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  // ============================================================
  // CONVERSÕES SEGURAS
  // ============================================================

  double _toDouble(
    dynamic value,
    double valorPadrao,
  ) {
    if (value == null) {
      return valorPadrao;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(
            value.replaceAll(',', '.'),
          ) ??
          valorPadrao;
    }

    return valorPadrao;
  }

  bool _toBool(
    dynamic value,
    bool valorPadrao,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is String) {
      final valor = value.toLowerCase().trim();

      if (valor == 'true' || valor == '1') {
        return true;
      }

      if (valor == 'false' || valor == '0') {
        return false;
      }
    }

    if (value is num) {
      return value != 0;
    }

    return valorPadrao;
  }

  String _toString(
    dynamic value,
    String valorPadrao,
  ) {
    if (value == null) {
      return valorPadrao;
    }

    return value.toString();
  }

  List<String> _toImages(dynamic value) {
    if (value == null || value is! List) {
      return [];
    }

    return value
        .whereType<String>()
        .where(
          (item) => item.trim().isNotEmpty,
        )
        .toList();
  }

  // ============================================================
  // CARREGAR DADOS
  // ============================================================

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _erroCarregamento = null;
      });
    }

    try {
      final dadosRemotos = await _firebaseService.getOrientacoes();

      final List<OrientacaoModel> orientacoesCarregadas = [];

      for (final item in dadosRemotos) {
        try {
          final String id = _toString(
            item['id'],
            DateTime.now().microsecondsSinceEpoch.toString(),
          );

          final String titulo = _toString(
            item['titulo'],
            'Orientação',
          );

          final String texto = _toString(
            item['texto'],
            '',
          );

          final bool expandido = _toBool(
            item['expandido'],
            true,
          );

          final double posX = _toDouble(
            item['posX'],
            50.0,
          );

          final double posY = _toDouble(
            item['posY'],
            50.0,
          );

          final double largura = _toDouble(
            item['largura'],
            600.0,
          );

          final double alturaTexto = _toDouble(
            item['alturaTexto'],
            500.0,
          );

          final List<String> imagens = _toImages(
            item['imagens'],
          );

          final model = OrientacaoModel(
            id: id,
            titulo: titulo,
            textoInicial: texto,
            expandido: expandido,
            posicao: Offset(posX, posY),
            largura: largura.clamp(
              350.0,
              1100.0,
            ),
            alturaTexto: alturaTexto.clamp(
              300.0,
              850.0,
            ),
            imagens: imagens,
          );

          model.controller.addListener(
            () => _agendarSalvamento(model),
          );

          orientacoesCarregadas.add(model);
        } catch (e, stackTrace) {
          debugPrint(
            'ERRO AO CONVERTER ORIENTAÇÃO: $e',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      if (!mounted) {
        for (final item in orientacoesCarregadas) {
          item.dispose();
        }

        return;
      }

      setState(() {
        _orientacoes.clear();
        _orientacoes.addAll(
          orientacoesCarregadas,
        );
      });

      if (_orientacoes.isEmpty && dadosRemotos.isEmpty) {
        _adicionarBlocoComDetalhes(
          id: '1',
          titulo: 'Orientação #1',
          texto: '',
          pos: const Offset(40, 30),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(e.toString());
      debugPrint(stackTrace.toString());

      if (mounted) {
        setState(() {
          _erroCarregamento = e.toString();
        });
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
  // SALVAMENTO COM DEBOUNCE
  // ============================================================

  void _agendarSalvamento(
    OrientacaoModel item,
  ) {
    _timersSalvamento[item.id]?.cancel();

    _timersSalvamento[item.id] = Timer(
      const Duration(milliseconds: 700),
      () {
        _salvarBloco(item);
      },
    );

    if (mounted) {
      setState(() {
        _ultimoSalvoId = null;
      });
    }
  }

  Future<void> _salvarBloco(
    OrientacaoModel item,
  ) async {
    _timersSalvamento[item.id]?.cancel();

    if (mounted) {
      setState(() {
        _salvandoIds.add(item.id);
      });
    }

    try {
      await _firebaseService.saveOrientacao(
        item.id,
        item.toJson(),
      );

      if (mounted) {
        setState(() {
          _salvandoIds.remove(item.id);
          _ultimoSalvoId = item.id;
        });

        Future.delayed(
          const Duration(seconds: 2),
          () {
            if (!mounted) {
              return;
            }

            if (_ultimoSalvoId == item.id) {
              setState(() {
                _ultimoSalvoId = null;
              });
            }
          },
        );
      }
    } catch (e) {
      debugPrint(
        'Erro ao salvar orientação ${item.id}: $e',
      );

      if (mounted) {
        setState(() {
          _salvandoIds.remove(item.id);
        });
      }
    }
  }

  // ============================================================
  // ADICIONAR BLOCO
  // ============================================================

  void _adicionarBlocoComDetalhes({
    required String id,
    required String titulo,
    required String texto,
    required Offset pos,
    bool expandido = true,
    double largura = 600.0,
    double altura = 500.0,
    List<String>? imagens,
  }) {
    final model = OrientacaoModel(
      id: id,
      titulo: titulo,
      textoInicial: texto,
      posicao: pos,
      expandido: expandido,
      largura: largura,
      alturaTexto: altura,
      imagens: imagens,
    );

    model.controller.addListener(
      () => _agendarSalvamento(model),
    );

    _orientacoes.add(model);

    _salvarBloco(model);
  }

  void _adicionarBloco() {
    final novoId = DateTime.now().millisecondsSinceEpoch.toString();

    final novaPos = Offset(
      80.0 + ((_orientacoes.length % 5) * 30),
      80.0 + ((_orientacoes.length % 5) * 30),
    );

    setState(() {
      _adicionarBlocoComDetalhes(
        id: novoId,
        titulo: 'Orientação #${_orientacoes.length + 1}',
        texto: '',
        pos: novaPos,
      );
    });
  }

  // ============================================================
  // IMAGENS
  // ============================================================

  Future<void> _adicionarImagens(
    OrientacaoModel item,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'webp',
        ],
      );

      if (result == null) {
        return;
      }

      final List<String> novasImagens = [];

      for (final file in result.files) {
        final bytes = file.bytes;

        if (bytes == null || bytes.isEmpty) {
          continue;
        }

        final String base64Imagem = base64Encode(bytes);

        String extensao = 'png';

        final nome = file.name.toLowerCase();

        if (nome.endsWith('.jpg') || nome.endsWith('.jpeg')) {
          extensao = 'jpeg';
        } else if (nome.endsWith('.webp')) {
          extensao = 'webp';
        }

        novasImagens.add(
          'data:image/$extensao;base64,$base64Imagem',
        );
      }

      if (novasImagens.isEmpty) {
        return;
      }

      setState(() {
        item.imagens.addAll(novasImagens);
        _cardComFoco = item.id;
      });

      await _salvarBloco(item);
    } catch (e) {
      debugPrint(
        'Erro ao adicionar imagem: $e',
      );
    }
  }

  Future<void> _colarPrint(
    OrientacaoModel item,
  ) async {
    if (_colandoImagem) {
      return;
    }

    setState(() {
      _cardComFoco = item.id;
      _colandoImagem = true;
    });

    try {
      final Uint8List? bytes = await Pasteboard.image;

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nenhuma imagem disponível. Permita o acesso à área de transferência ou selecione uma imagem.'),
          ));
        }
        return;
      }

      final String base64Imagem = base64Encode(bytes);

      final String imagemBase64 = 'data:image/png;base64,$base64Imagem';

      setState(() {
        item.imagens.add(imagemBase64);
      });

      await _salvarBloco(item);
    } catch (e) {
      debugPrint(
        'Erro ao colar print: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _colandoImagem = false;
        });
      }
    }
  }

  Future<void> _removerImagem(
    OrientacaoModel item,
    int index,
  ) async {
    if (index < 0 || index >= item.imagens.length) {
      return;
    }

    setState(() {
      item.imagens.removeAt(index);
    });

    await _salvarBloco(item);
  }

  Uint8List _decodeImagem(
    String imagem,
  ) {
    try {
      String valor = imagem;

      if (valor.contains(',')) {
        valor = valor.substring(
          valor.indexOf(',') + 1,
        );
      }

      return Uint8List.fromList(
        base64Decode(valor),
      );
    } catch (_) {
      return Uint8List(0);
    }
  }

  // ============================================================
  // VISUALIZAR IMAGEM
  // ============================================================

  void _visualizarImagem(
    String imagem,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (context) {
        AppAppearance.watch(context);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.memory(
                    _decodeImagem(imagem),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: CoresApp.superficie,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: CoresApp.textoSecundario,
                              size: 50,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Não foi possível visualizar esta imagem.',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // EXCLUIR BLOCO
  // ============================================================

  Future<void> _removerBloco(
    OrientacaoModel item,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: CoresApp.erro,
              ),
              SizedBox(width: 10),
              Text(
                'Excluir orientação',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Deseja realmente excluir "${item.titulo}"?\n\nEssa ação não poderá ser desfeita.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: AppPalette.onPrimary,
              ),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    try {
      await _firebaseService.deleteOrientacao(
        item.id,
      );
    } catch (e) {
      debugPrint(
        'Erro ao excluir orientação: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível excluir a orientação.',
            ),
          ),
        );
      }

      return;
    }

    if (!mounted) {
      item.dispose();
      return;
    }

    setState(() {
      item.dispose();
      _orientacoes.remove(item);

      if (_cardComFoco == item.id) {
        _cardComFoco = null;
      }

      _timersSalvamento[item.id]?.cancel();
      _timersSalvamento.remove(item.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Orientação excluída com sucesso.',
        ),
      ),
    );
  }

  // ============================================================
  // MODAL
  // ============================================================

  void _abrirModalOrientacao(
    OrientacaoModel item,
  ) {
    double modalWidth = item.largura;
    double modalHeight = item.alturaTexto;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        AppAppearance.watch(context);
        return StatefulBuilder(
          builder: (
            context,
            setStateModal,
          ) {
            AppAppearance.watch(context);

            return Center(
              child: Stack(
                children: [
                  Container(
                    width: modalWidth,
                    height: modalHeight,
                    constraints: const BoxConstraints(
                      minWidth: 350,
                      maxWidth: 1100,
                      minHeight: 300,
                      maxHeight: 850,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.superficie,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: CoresApp.borda,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCabecalhoModal(
                            item,
                            context,
                          ),
                          Divider(
                            color: CoresApp.borda,
                            height: 1,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTituloSecao(
                                    'CONTEÚDO',
                                    Icons.description_outlined,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: item.controller,
                                      maxLines: null,
                                      expands: true,
                                      textAlignVertical: TextAlignVertical.top,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 14,
                                        height: 1.55,
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Digite aqui a orientação, procedimento ou regra...',
                                        hintStyle: TextStyle(
                                          color: CoresApp.textoSecundario,
                                          fontSize: 13,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: CoresApp.borda,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: CoresApp.primaria,
                                            width: 1.4,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor:
                                            CoresApp.fundo.withValues(alpha: 0.45),
                                        contentPadding:
                                            const EdgeInsets.all(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTituloSecao(
                                    'ANEXOS',
                                    Icons.image_outlined,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildAreaImagens(
                                    item,
                                    setStateModal,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildRodapeModal(
                            item,
                            modalWidth,
                            modalHeight,
                            context,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setStateModal(() {
                            modalWidth = (modalWidth + details.delta.dx)
                                .clamp(350.0, 1100.0);

                            modalHeight = (modalHeight + details.delta.dy)
                                .clamp(300.0, 850.0);

                            item.largura = modalWidth;
                            item.alturaTexto = modalHeight;
                          });
                        },
                        onPanEnd: (_) {
                          _salvarBloco(item);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: CoresApp.primaria.withValues(alpha: 0.18),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 13,
                            color: CoresApp.destaque,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCabecalhoModal(
    OrientacaoModel item,
    BuildContext dialogContext,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        16,
        12,
        14,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CoresApp.primaria.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: CoresApp.primaria,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Editor de orientação',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          _buildIndicadorSalvamento(item),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            icon: Icon(
              Icons.close_rounded,
              color: CoresApp.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicadorSalvamento(
    OrientacaoModel item,
  ) {
    final salvando = _salvandoIds.contains(item.id);

    final salvo = _ultimoSalvoId == item.id;

    if (salvando) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: CoresApp.primaria,
            ),
          ),
          SizedBox(width: 6),
          Text(
            'Salvando...',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    if (salvo) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 15,
            color: CoresApp.sucesso,
          ),
          SizedBox(width: 5),
          Text(
            'Salvo',
            style: TextStyle(
              color: CoresApp.sucesso,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTituloSecao(
    String titulo,
    IconData icone,
  ) {
    return Row(
      children: [
        Icon(
          icone,
          size: 15,
          color: CoresApp.primaria,
        ),
        const SizedBox(width: 7),
        Text(
          titulo,
          style: TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildAreaImagens(
    OrientacaoModel item,
    StateSetter setStateModal,
  ) {
    return SizedBox(
      height: 86,
      child: Row(
        children: [
          _buildBotaoColarPrint(item),
          const SizedBox(width: 8),
          _buildBotaoAdicionarImagem(item),
          if (item.imagens.isNotEmpty) const SizedBox(width: 12),
          if (item.imagens.isNotEmpty)
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.imagens.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return _buildMiniatura(
                    item,
                    index,
                    setStateModal,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBotaoAdicionarImagem(
    OrientacaoModel item,
  ) {
    return Tooltip(
      message: 'Adicionar imagens',
      child: InkWell(
        onTap: () => _adicionarImagens(item),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 92,
          height: 76,
          decoration: BoxDecoration(
            color: CoresApp.fundo.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: CoresApp.borda,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                color: CoresApp.primaria,
                size: 22,
              ),
              SizedBox(height: 5),
              Text(
                'Adicionar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniatura(
    OrientacaoModel item,
    int index,
    StateSetter setStateModal,
  ) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _visualizarImagem(
            item.imagens[index],
          ),
          child: Container(
            width: 80,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: CoresApp.borda,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.memory(
                _decodeImagem(
                  item.imagens[index],
                ),
                width: 80,
                height: 76,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    Icons.broken_image_outlined,
                    color: CoresApp.textoSecundario,
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                setStateModal(() {
                  item.imagens.removeAt(index);
                });

                await _salvarBloco(item);
              },
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 11,
                  color: AppPalette.text,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRodapeModal(
    OrientacaoModel item,
    double modalWidth,
    double modalHeight,
    BuildContext dialogContext,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        11,
        20,
        11,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CoresApp.borda,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: CoresApp.textoSecundario,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'As alterações são salvas automaticamente.',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 10,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              item.largura = modalWidth;
              item.alturaTexto = modalHeight;

              _salvarBloco(item);

              Navigator.of(dialogContext).pop();
            },
            child: Text(
              'Salvar e Fechar',
              style: TextStyle(
                color: CoresApp.primaria,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTÃO COLAR PRINT
  // ============================================================

  Widget _buildBotaoColarPrint(
    OrientacaoModel item,
  ) {
    final bool selecionado = _cardComFoco == item.id;

    return Tooltip(
      message: 'Colar print (Ctrl + V)',
      child: InkWell(
        onTap: () => _colarPrint(item),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 92,
          height: 76,
          decoration: BoxDecoration(
            color: selecionado
                ? CoresApp.primaria.withValues(alpha: 0.12)
                : CoresApp.fundo.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selecionado ? CoresApp.primaria : CoresApp.borda,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.content_paste_rounded,
                color: CoresApp.primaria,
                size: 21,
              ),
              const SizedBox(height: 5),
              Text(
                _colandoImagem && selecionado ? 'Colando...' : 'Colar print',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _pesquisaController.dispose();

    for (final timer in _timersSalvamento.values) {
      timer.cancel();
    }

    _timersSalvamento.clear();

    for (final item in _orientacoes) {
      item.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(
            color: CoresApp.primaria,
          ),
        ),
      );
    }

    final orientacoesFiltradas = _orientacoes.where((item) {
      return item.titulo.toLowerCase().contains(
            _filtroPesquisa.toLowerCase(),
          );
    }).toList();

    final totalImagens = _orientacoes.fold<int>(
      0,
      (total, item) => total + item.imagens.length,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (_) {},
          userName: '',
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCabecalhoPagina(
            totalImagens,
          ),
          if (_erroCarregamento != null) _buildErro(),
          Expanded(
            child: orientacoesFiltradas.isEmpty && _erroCarregamento == null
                ? _buildEstadoVazio()
                : LayoutBuilder(
                    builder: (
                      context,
                      constraints,
                    ) {
                      AppAppearance.watch(context);

                      final largura = constraints.maxWidth;

                      final int colunas = largura >= 1200
                          ? 3
                          : largura >= 800
                              ? 2
                              : 1;

                      final double espacamento = largura >= 1200 ? 10 : 9;

                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          4,
                          20,
                          25,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: colunas,
                          crossAxisSpacing: espacamento,
                          mainAxisSpacing: espacamento,
                          mainAxisExtent: largura >= 1200 ? 76 : 78,
                        ),
                        itemCount: orientacoesFiltradas.length,
                        itemBuilder: (
                          context,
                          index,
                        ) {
                          return _buildCardOrientacao(
                            orientacoesFiltradas[index],
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  // ============================================================
  // CABEÇALHO UNIFICADO
  // ============================================================

  Widget _buildCabecalhoPagina(
    int totalImagens,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        16,
        20,
        12,
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          AppAppearance.watch(context);

          final largura = constraints.maxWidth;

          final bool compacto = largura < 1050;
          final bool muitoCompacto = largura < 760;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(
              muitoCompacto ? 14 : 18,
            ),
            decoration: BoxDecoration(
              color: CoresApp.superficie.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CoresApp.borda.withValues(alpha: 0.9),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compacto)
                  _buildCabecalhoAmplo(
                    totalImagens,
                    largura,
                  )
                else
                  _buildCabecalhoCompacto(
                    totalImagens,
                    muitoCompacto,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCabecalhoAmplo(
    int totalImagens,
    double largura,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildIconeTitulo(),
        const SizedBox(width: 14),
        Expanded(
          flex: 3,
          child: _buildTituloPagina(),
        ),
        const SizedBox(width: 20),
        _buildEstatistica(
          Icons.auto_awesome_mosaic_outlined,
          '${_orientacoes.length}',
          'orientações',
        ),
        const SizedBox(width: 8),
        _buildEstatistica(
          Icons.collections_outlined,
          '$totalImagens',
          'imagens',
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: largura > 1350 ? 300 : 245,
          child: _buildPesquisa(),
        ),
        const SizedBox(width: 10),
        _buildBotaoNovaOrientacao(),
      ],
    );
  }

  Widget _buildCabecalhoCompacto(
    int totalImagens,
    bool muitoCompacto,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildIconeTitulo(),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTituloPagina(),
            ),
            if (!muitoCompacto) ...[
              _buildEstatistica(
                Icons.auto_awesome_mosaic_outlined,
                '${_orientacoes.length}',
                'orientações',
              ),
              const SizedBox(width: 8),
              _buildEstatistica(
                Icons.collections_outlined,
                '$totalImagens',
                'imagens',
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (muitoCompacto)
          Row(
            children: [
              Expanded(
                child: _buildEstatistica(
                  Icons.auto_awesome_mosaic_outlined,
                  '${_orientacoes.length}',
                  'orientações',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEstatistica(
                  Icons.collections_outlined,
                  '$totalImagens',
                  'imagens',
                ),
              ),
            ],
          ),
        if (muitoCompacto) const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildPesquisa(),
            ),
            const SizedBox(width: 10),
            _buildBotaoNovaOrientacao(
              compacto: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIconeTitulo() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CoresApp.primaria.withValues(alpha: 0.20),
            CoresApp.primaria.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CoresApp.primaria.withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: CoresApp.primaria.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.lightbulb_outline_rounded,
        color: CoresApp.primaria,
        size: 25,
      ),
    );
  }

  Widget _buildTituloPagina() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Orientações',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: CoresApp.textoPrincipal,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Consulte e mantenha seus procedimentos organizados.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: CoresApp.textoSecundario.withValues(alpha: 0.9),
            fontSize: 10.5,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildEstatistica(
    IconData icon,
    String valor,
    String legenda,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: CoresApp.fundo.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: CoresApp.primaria.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 14,
              color: CoresApp.primaria,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            valor,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            legenda,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoNovaOrientacao({
    bool compacto = false,
  }) {
    if (compacto) {
      return Tooltip(
        message: 'Nova orientação',
        child: SizedBox(
          height: 44,
          width: 46,
          child: ElevatedButton(
            onPressed: _adicionarBloco,
            style: ElevatedButton.styleFrom(
              backgroundColor: CoresApp.primaria,
              foregroundColor: AppPalette.onPrimary,
              elevation: 3,
              shadowColor: CoresApp.primaria.withValues(alpha: 0.25),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const Icon(
              Icons.add_rounded,
              size: 21,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: _adicionarBloco,
        icon: const Icon(
          Icons.add_rounded,
          size: 18,
        ),
        label: const Text(
          'Nova orientação',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: CoresApp.primaria,
          foregroundColor: AppPalette.onPrimary,
          elevation: 3,
          shadowColor: CoresApp.primaria.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
    );
  }

  Widget _buildPesquisa() {
    return TextField(
      controller: _pesquisaController,
      onChanged: (value) {
        setState(() {
          _filtroPesquisa = value;
        });
      },
      style: TextStyle(
        color: CoresApp.textoPrincipal,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Pesquisar orientação...',
        hintStyle: TextStyle(
          color: CoresApp.textoSecundario,
          fontSize: 11,
        ),
        prefixIcon: Container(
          width: 42,
          alignment: Alignment.center,
          child: Icon(
            Icons.search_rounded,
            color: CoresApp.textoSecundario,
            size: 18,
          ),
        ),
        suffixIcon: _pesquisaController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Limpar pesquisa',
                icon: Icon(
                  Icons.close_rounded,
                  color: CoresApp.textoSecundario,
                  size: 15,
                ),
                onPressed: () {
                  setState(() {
                    _pesquisaController.clear();
                    _filtroPesquisa = '';
                  });
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.borda,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.borda,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.primaria,
            width: 1.3,
          ),
        ),
        filled: true,
        fillColor: CoresApp.fundo.withValues(alpha: 0.60),
      ),
    );
  }

  // ============================================================
  // ERRO
  // ============================================================

  Widget _buildErro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        10,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: CoresApp.erro.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: CoresApp.erro.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: CoresApp.erro.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: CoresApp.erro,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Não foi possível carregar as orientações do Firebase.',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 11,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _carregarDados,
              icon: const Icon(
                Icons.refresh_rounded,
                size: 15,
              ),
              label: const Text(
                'Tentar novamente',
              ),
              style: TextButton.styleFrom(
                foregroundColor: CoresApp.primaria,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  Widget _buildEstadoVazio() {
    final bool pesquisando = _filtroPesquisa.trim().isNotEmpty;

    return Center(
      child: Container(
        width: 430,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: CoresApp.superficie.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CoresApp.borda,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CoresApp.primaria.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: CoresApp.primaria.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(
                pesquisando
                    ? Icons.search_off_rounded
                    : Icons.lightbulb_outline_rounded,
                color: CoresApp.primaria,
                size: 31,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pesquisando
                  ? 'Nenhuma orientação encontrada'
                  : 'Nenhuma orientação cadastrada',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pesquisando
                  ? 'Tente pesquisar usando outro termo.'
                  : 'Crie sua primeira orientação para manter seus procedimentos organizados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 11,
                height: 1.55,
              ),
            ),
            if (!pesquisando) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _adicionarBloco,
                icon: const Icon(
                  Icons.add_rounded,
                  size: 17,
                ),
                label: const Text(
                  'Criar orientação',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoresApp.primaria,
                  foregroundColor: AppPalette.onPrimary,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _buildCardOrientacao(
    OrientacaoModel item,
  ) {
    return _OrientacaoCard(
      item: item,
      onTap: () => _abrirModalOrientacao(item),
      onDelete: () => _removerBloco(item),
    );
  }
}

// ============================================================================
// CARD — PAINEL COMPACTO PROFISSIONAL
// ============================================================================

class _OrientacaoCard extends StatefulWidget {
  final OrientacaoModel item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _OrientacaoCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_OrientacaoCard> createState() => _OrientacaoCardState();
}

class _OrientacaoCardState extends State<_OrientacaoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final item = widget.item;

    final bool possuiConteudo = item.controller.text.trim().isNotEmpty;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
        });
      },
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _hovered ? -1 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: _hovered
              ? CoresApp.superficie.withValues(alpha: 0.98)
              : CoresApp.superficie.withValues(alpha: 0.91),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? CoresApp.primaria.withValues(alpha: 0.42)
                : CoresApp.borda.withValues(alpha: 0.85),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: _hovered ? 0.16 : 0.06,
              ),
              blurRadius: _hovered ? 12 : 6,
              offset: Offset(
                0,
                _hovered ? 4 : 2,
              ),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.transparent,
              splashColor: CoresApp.primaria.withValues(alpha: 0.05),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 3,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? CoresApp.primaria
                          : CoresApp.primaria.withValues(alpha: 0.50),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(
                              milliseconds: 150,
                            ),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _hovered
                                  ? CoresApp.primaria.withValues(alpha: 0.15)
                                  : CoresApp.primaria.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: CoresApp.primaria.withValues(
                                  alpha: _hovered ? 0.26 : 0.12,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.lightbulb_outline_rounded,
                              color: CoresApp.primaria,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            flex: 4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _hovered
                                        ? CoresApp.textoPrincipal
                                        : CoresApp.destaque,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      possuiConteudo
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.edit_note_rounded,
                                      size: 10,
                                      color: possuiConteudo
                                          ? CoresApp.sucesso
                                          : CoresApp.textoSecundario,
                                    ),
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    Flexible(
                                      child: Text(
                                        possuiConteudo
                                            ? 'Conteúdo disponível'
                                            : 'Sem conteúdo',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: CoresApp.textoSecundario,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            flex: 5,
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 7,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: CoresApp.borda.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                possuiConteudo
                                    ? item.controller.text.replaceAll(
                                        '\n',
                                        ' ',
                                      )
                                    : 'Clique para adicionar o conteúdo...',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: possuiConteudo
                                      ? CoresApp.textoSecundario
                                      : CoresApp.textoSecundario.withValues(
                                          alpha: 0.55,
                                        ),
                                  fontSize: 9.5,
                                  height: 1.25,
                                  fontStyle: possuiConteudo
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          if (item.imagens.isNotEmpty)
                            _buildIndicadorAnexos(
                              item.imagens.length,
                            ),
                          if (item.imagens.isNotEmpty) const SizedBox(width: 5),
                          AnimatedOpacity(
                            opacity: _hovered ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: IgnorePointer(
                              ignoring: !_hovered,
                              child: Container(
                                width: 27,
                                height: 27,
                                decoration: BoxDecoration(
                                  color: CoresApp.erro.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: IconButton(
                                  tooltip: 'Excluir orientação',
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: CoresApp.erro,
                                    size: 14,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: widget.onDelete,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 130),
                            width: 25,
                            height: 27,
                            decoration: BoxDecoration(
                              color: _hovered
                                  ? CoresApp.primaria.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: _hovered
                                  ? CoresApp.primaria
                                  : CoresApp.textoSecundario,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndicadorAnexos(
    int quantidade,
  ) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: CoresApp.fundo.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 11,
            color: CoresApp.primaria,
          ),
          const SizedBox(width: 4),
          Text(
            '$quantidade',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
