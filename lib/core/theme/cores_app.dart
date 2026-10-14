import 'app_palette.dart';
import 'app_visuals.dart';
import 'package:flutter/material.dart';

/// ===============================================================
/// CORES GERAIS DO APLICATIVO (MIDNIGHT EXECUTIVE TECH)
/// ===============================================================
class CoresApp {
  CoresApp._();

  // =============================================================
  // FUNDOS (Tons profundos de azul-marinho e slate)
  // =============================================================

  static Color get fundo =>
      AppPalette.background; // Fundo principal ultra-profundo
  static Color get fundoSecundario =>
      AppPalette.field; // Fundo secundário sutil
  static Color get superficie =>
      AppPalette.surface; // Superfície de cartões padrão
  static Color get superficieClara => AppPalette.raised; // Superfície elevada
  static Color get superficieEscura =>
      AppPalette.field; // Superfície de destaque escuro
  static Color get grafico =>
      AppPalette.surface; // Superfície de cartões padrão

  // =============================================================
  // CORES PRINCIPAIS
  // =============================================================

  static Color get primaria =>
      AppPalette.primary; // Azul Ciano moderno e vibrante
  static Color get secundaria => AppPalette.primary; // Azul claro complementar
  static Color get destaque =>
      AppPalette.accent; // Destaque tecnológico neon suave

  // =============================================================
  // TEXTOS
  // =============================================================

  static Color get textoPrincipal =>
      AppPalette.text; // Branco quase puro para máxima leitura
  static Color get textoSecundario =>
      AppPalette.secondary; // Cinza slate elegante
  static Color get textoFraco => AppPalette.muted; // Cinza sutil para detalhes
  static Color get textoDesabilitado => AppPalette.muted;

  // =============================================================
  // ESTADOS
  // =============================================================

  static Color get sucesso => AppPalette.success; // Verde esmeralda moderno
  static Color get erro => AppPalette.danger; // Vermelho vivo refinado
  static Color get aviso => AppPalette.warning; // Âmbar elegante
  static Color get informacao => AppPalette.primary; // Azul informativo

  // =============================================================
  // DESTAQUES
  // =============================================================

  static Color get destaqueAmarelo => AppPalette.warning;
  static Color get destaqueVermelho => AppPalette.danger;
  static Color get destaqueVerde => AppPalette.success;
  static Color get destaqueAzul => AppPalette.primary;

  // =============================================================
  // BORDAS
  // =============================================================

  static Color get borda => AppPalette.border; // Linhas de contorno discretas
  static Color get bordaSuave => AppVisuals.divider;

  // =============================================================
  // SOMBRAS / OVERLAYS
  // =============================================================

  static const Color overlay = Color(0x80000000);

  /// Compatibilidade com telas que utilizem fundoEscuro.
  static Color get fundoEscuro => AppPalette.background;
}

/// ===============================================================
/// CORES ESPECÍFICAS DO DASHBOARD
/// ===============================================================
class CoresDashboard {
  CoresDashboard._();

  // =============================================================
  // ESTRUTURA
  // =============================================================

  static Color get fundo => AppPalette.background;
  static Color get fundoSecundario => AppPalette.field;
  static Color get card => AppPalette.surface;
  static Color get cardHover => AppPalette.raised;
  static Color get cabecalhoTabela => AppPalette.header;

  // =============================================================
  // GRÁFICOS
  // =============================================================

  static Color get graficoHoras => AppPalette.accent;
  static Color get graficoProjetos => AppPalette.primary;
  static Color get graficoConcluidos => AppPalette.success;
  static Color get graficoAtrasados => AppPalette.danger;
  static Color get graficoAndamento => AppPalette.warning;

  // =============================================================
  // STATUS
  // =============================================================

  static Color get statusInicial => AppPalette.warning;
  static Color get statusTrabalhando => AppPalette.success;
  static Color get statusAndamento => AppPalette.primary;
  static Color get statusFinalizado => AppPalette.primary;

  // =============================================================
  // TABELA DE PROJETOS
  // =============================================================

  static Color get tabelaFundo => AppPalette.surface;
  static Color get tabelaCabecalho => AppPalette.header;
  static Color get tabelaLinhaSelecionada =>
      AppPalette.primary.withValues(alpha: 0.12);
  static Color get tabelaLinhaExpandida =>
      AppPalette.primary.withValues(alpha: 0.045);
  static Color get tabelaLinhaEtapa => AppPalette.subtle;
  static Color get tabelaLinhaExecucao => AppPalette.raised;
  static const Color tabelaLinhaRegistrada = Color(0x1A10B981);
  static Color get tabelaBorda => AppPalette.border;
  static Color get tabelaDivisor => AppVisuals.divider;
  static Color get tabelaHover => AppPalette.subtle;
  static Color get tabelaHover1 => AppPalette.subtle;

  // =============================================================
  // ALERTAS
  // =============================================================

  static Color get alerta => AppPalette.warning;
  static Color get atrasado => AppPalette.danger;
  static Color get proximoVencimento => AppPalette.warning;
  static Color get dentroPrazo => AppPalette.success;
}

/// ===============================================================
/// CORES ESPECÍFICAS DAS TELAS
/// ===============================================================
class CoresTelas {
  CoresTelas._();

  // =============================================================
  // LOGIN / AUTENTICAÇÃO
  // =============================================================

  static Color get fundoLogin => AppPalette.background;
  static Color get painelLogin => AppPalette.surface;

  // =============================================================
  // FORMULÁRIOS
  // =============================================================

  static Color get campoFormulario => AppPalette.field;
  static Color get campoFormularioFoco => AppPalette.raised;

  // =============================================================
  // MODAIS
  // =============================================================

  static Color get fundoModal => AppPalette.surface;
  static Color get fundoModalSecundario => AppPalette.field;

  // =============================================================
  // SUPORTE / ATALHOS DE TELA
  // =============================================================

  static Color get fundoSuperficie => AppPalette.surface;
  static Color get fundoCard => AppPalette.surface;
  static Color get cabecalhoTabela => AppPalette.header;
  static Color get fundoPrincipal => AppPalette.background;
}

/// ===============================================================
/// DIMENSÕES E TIPOGRAFIA DO APLICATIVO
/// ===============================================================
class TamanhosApp {
  TamanhosApp._();

  // =============================================================
  // TABELAS
  // =============================================================

  static const double tabelaFonteCabecalho = 11;
  static const double tabelaFonte = 11;
  static const double tabelaFonteSecundaria = 10.5;
  static const double tabelaFonteStatus = 9.5;
  static const double tabelaFonteAcao = 9.5;
  static const double tabelaEspacamentoColunas = 8;
  static const double tabelaMargemHorizontal = 8;
  static const double tabelaAlturaMinima = 350;

  // =============================================================
  // ÍCONES
  // =============================================================

  static const double iconeTabela = 17;
  static const double iconeAcao = 18;
  static const double iconeStatus = 14;

  // =============================================================
  // BORDAS
  // =============================================================

  static const double raioTabela = 12;
  static const double raioBadge = 5;
  static const double raioBotao = 6;
  static const double espessuraBorda = 0.8;

  // =============================================================
  // ESPAÇAMENTOS
  // =============================================================

  static const double espacamentoPequeno = 4;
  static const double espacamentoMedio = 8;
  static const double espacamentoGrande = 12;
}
