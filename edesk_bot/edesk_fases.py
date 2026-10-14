import asyncio
import json
import os
import re
import sys
from send_progress import observe_log, completed
from phase_confirmation import read_phase_rows, mismatched_phases, close_new_duplicate_requests
import unicodedata
from pathlib import Path
from datetime import datetime

from playwright.async_api import async_playwright
from config import HEADLESS


# ================================================================
# CONFIGURAÇÃO
# ================================================================

BASE_URL = "https://promob.e-desk.com.br"

BASE_DIR = Path(__file__).resolve().parent

# Dados graváveis do E-Desk não podem ficar dentro de Program Files.
# Perfil, logs e diagnósticos ficam no LocalAppData do usuário.
LOCAL_APP_DATA = Path(
    os.environ.get(
        "LOCALAPPDATA",
        str(Path.home() / "AppData" / "Local"),
    )
)

EDESK_DATA_DIR = Path(
    os.environ.get("EDESK_DATA_DIR")
    or LOCAL_APP_DATA / "Gerenciador de Horas" / "edesk_bot"
)
PROFILE_DIR = EDESK_DATA_DIR / "perfil"
LOG_DIR = EDESK_DATA_DIR / "logs"

PROFILE_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

LOG_FILE = LOG_DIR / "exploracao_edesk.log"

DIAGNOSTICO_HTML = LOG_DIR / "fases_diagnostico.html"


# ================================================================
# SEGURANÇA
# ================================================================

# IMPORTANTÍSSIMO:
#
# False = nenhuma rotina poderá efetivamente salvar no E-Desk.
# True  = permite que salvar_fases() execute o clique em Salvar.
#
# Enquanto estivermos identificando o Trabalho correto para ajuste,
# esta configuração deve permanecer FALSE.

PERMITIR_SALVAMENTO = True


# ================================================================
# LOG
# ================================================================

def log(msg):
    observe_log(msg)
    texto = str(msg)

    linha = (
        f"[E-Desk][Python] "
        f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
        f"{texto}"
    )

    print(linha, flush=True)

    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(linha + "\n")
    except Exception:
        pass


# ================================================================
# NORMALIZAÇÃO
# ================================================================

def normalizar(texto):
    if texto is None:
        return ""

    texto = str(texto).strip().lower()

    texto = unicodedata.normalize(
        "NFD",
        texto
    )

    texto = "".join(
        c
        for c in texto
        if unicodedata.category(c) != "Mn"
    )

    texto = re.sub(
        r"\s+",
        " ",
        texto
    )

    return texto


def somente_numeros(texto):
    if texto is None:
        return ""

    return re.sub(
        r"\D",
        "",
        str(texto)
    )


# ================================================================
# NORMALIZAÇÃO DOS NOMES DAS FASES
# ================================================================

def chave_fase(nome):
    valor = normalizar(nome)

    # ------------------------------------------------------------
    # Remove prefixos usados pelo E-Desk
    # ------------------------------------------------------------

    prefixos = [
        "promob - ",
        "promob-",
        "promob ",
    ]

    for prefixo in prefixos:

        if valor.startswith(prefixo):

            valor = valor[len(prefixo):].strip()

            break

    # ------------------------------------------------------------
    # Normaliza equivalências de nomes
    # ------------------------------------------------------------

    equivalencias = {
        "gerencia do projeto": "gerenciamento de projetos",
        "gerenciamento do projeto": "gerenciamento de projetos",
        "gerenciamento de projeto": "gerenciamento de projetos",

        "contato inicial": "contato inicial",

        "levantamento de escopo": "levantamento de escopo",

        "desenvolvimento": "desenvolvimento",

        "implantacao": "implantacao",

        "pos implantacao": "pos implantacao",
        "pos-implantacao": "pos implantacao",
    }

    return equivalencias.get(
        valor,
        valor
    )


# ================================================================
# DATA
# ================================================================

def formatar_data(valor):
    if not valor:
        return ""

    valor = str(valor).strip()

    if not valor:
        return ""

    if re.match(
        r"^\d{2}/\d{2}/\d{4}$",
        valor
    ):
        return valor

    try:

        if "T" in valor:
            valor = valor.split("T")[0]

        dt = datetime.strptime(
            valor,
            "%Y-%m-%d"
        )

        return dt.strftime(
            "%d/%m/%Y"
        )

    except Exception:
        pass

    return valor


# ================================================================
# REMOVER REQUEST TEMPORÁRIO
#
# IMPORTANTE:
#
# O Flutter cria um diretório temporário para enviar o JSON.
# Como este processo pode permanecer aberto por bastante tempo,
# removemos o arquivo imediatamente após a leitura.
#
# Assim, as credenciais não ficam persistidas no request.json.
# ================================================================

def remover_request_temporario(caminho):
    try:

        if not caminho.exists():
            return

        nome_pasta = caminho.parent.name

        eh_temporario = (
            nome_pasta.startswith("edesk_request_")
            or nome_pasta.startswith("edesk_request_bg_")
        )

        if not eh_temporario:
            return

        caminho.unlink()

        log(
            "Arquivo JSON temporário removido após leitura."
        )

        try:

            caminho.parent.rmdir()

        except Exception:
            pass

    except Exception as e:

        log(
            f"Aviso: não foi possível remover "
            f"o request temporário: {e}"
        )


# ================================================================
# REQUEST / RESPONSE
# ================================================================

def ler_request():
    """
    Aceita os três formatos:

    1. Caminho para um arquivo JSON.
    2. JSON diretamente como argumento.
    3. JSON enviado pelo STDIN.
    """

    try:

        # ============================================================
        # 1. ARGUMENTO
        # ============================================================

        if len(sys.argv) > 1:

            argumento = sys.argv[1].strip()

            caminho = Path(argumento)

            if caminho.exists() and caminho.is_file():

                log(
                    f"Lendo JSON do arquivo: {caminho}"
                )

                with open(
                    caminho,
                    "r",
                    encoding="utf-8"
                ) as arquivo:

                    conteudo = arquivo.read().strip()

                if not conteudo:

                    raise Exception(
                        f"O arquivo JSON está vazio: {caminho}"
                    )

                dados = json.loads(
                    conteudo
                )

                log(
                    "JSON carregado com sucesso do arquivo."
                )

                # ----------------------------------------------------
                # REMOVE SOMENTE REQUESTS TEMPORÁRIOS DO APP
                # ----------------------------------------------------

                remover_request_temporario(
                    caminho
                )

                return dados

            if argumento.startswith("{"):

                log(
                    "JSON recebido diretamente como argumento."
                )

                return json.loads(
                    argumento
                )

            raise Exception(
                "O argumento recebido não é um arquivo JSON "
                f"nem um JSON válido: {argumento}"
            )

        # ============================================================
        # 2. STDIN
        # ============================================================

        bruto = sys.stdin.read().strip()

        if bruto:

            log(
                "JSON recebido via STDIN."
            )

            return json.loads(
                bruto
            )

        return {}

    except json.JSONDecodeError as e:

        log(
            f"JSON inválido: {e}"
        )

        raise

    except Exception as e:

        log(
            f"Erro lendo JSON: {e}"
        )

        raise


def responder(dados):

    try:

        print(
            json.dumps(
                dados,
                ensure_ascii=False
            ),
            flush=True
        )

    except Exception as e:

        log(
            f"Erro ao responder JSON: {e}"
        )


# ================================================================
# CREDENCIAIS E-DESK
# ================================================================

def obter_credenciais_edesk(request):
    """
    Lê as credenciais enviadas pelo Flutter.

    Formato preferencial:

        {
            "edeskCredenciais": {
                "email": "...",
                "senha": "..."
            }
        }

    Também aceita os formatos antigos/diretos:

        {
            "edeskEmail": "...",
            "edeskSenha": "..."
        }

    IMPORTANTE:
    A senha nunca é registrada no log.
    """

    email = ""
    senha = ""

    # ============================================================
    # FORMATO PRINCIPAL
    # ============================================================

    credenciais = request.get(
        "edeskCredenciais"
    )

    if isinstance(
        credenciais,
        dict
    ):

        email = str(
            credenciais.get(
                "email",
                ""
            )
            or ""
        ).strip()

        senha = str(
            credenciais.get(
                "senha",
                ""
            )
            or ""
        )

    # ============================================================
    # FALLBACK
    # ============================================================

    if not email:

        email = str(
            request.get(
                "edeskEmail",
                ""
            )
            or ""
        ).strip()

    if not senha:

        senha = str(
            request.get(
                "edeskSenha",
                ""
            )
            or ""
        )

    return email, senha


# ================================================================
# LOGIN - AUXILIAR PARA LOCALIZAR ELEMENTO VISÍVEL
# ================================================================

async def localizar_primeiro_visivel(
    page,
    seletores
):
    """
    Procura o primeiro elemento visível.

    A busca é feita:
    - página principal;
    - todos os frames.
    """

    raizes = [page]

    try:

        for frame in page.frames:

            if frame not in raizes:
                raizes.append(frame)

    except Exception:
        pass

    for raiz in raizes:

        for seletor in seletores:

            try:

                loc = raiz.locator(
                    seletor
                ).first

                if await loc.count() == 0:
                    continue

                if not await loc.is_visible():
                    continue

                return loc

            except Exception:
                continue

    return None


# ================================================================
# LOGIN - SELETORES PROMOB ID
# ================================================================

SELETORES_EMAIL_LOGIN = [
    "input[placeholder='nome@exemplo.com']",
    "input[type='email']",
    "input[autocomplete='username']",
    "input[name*='email' i]",
    "input[id*='email' i]",
]

SELETORES_SENHA_LOGIN = [
    "input[placeholder='Senha']",
    "input[type='password']",
    "input[autocomplete='current-password']",
    "input[name*='senha' i]",
    "input[id*='senha' i]",
    "input[name*='password' i]",
    "input[id*='password' i]",
]

SELETORES_ENTRAR_LOGIN = [
    "button:has-text('Entrar')",
    "input[type='submit'][value*='Entrar']",
    "input[value*='Entrar']",
    "button[type='submit']",
]


# ================================================================
# LOGIN - CONFIRMAR SESSÃO
# ================================================================

async def login_confirmado(page):

    try:

        url = page.url

        if (
            "/Portal/PortalAtendente.aspx" in url
        ):
            return True

        botao_comentarios = page.locator(
            "#cph1_BtCom"
        )

        if await botao_comentarios.count() > 0:

            try:

                if await botao_comentarios.is_visible():
                    return True

            except Exception:
                return True

    except Exception:
        pass

    return False


# ================================================================
# LOGIN - TELA DE LOGIN DETECTADA
# ================================================================

async def tela_login_detectada(page):

    try:

        campo_senha = await localizar_primeiro_visivel(
            page,
            SELETORES_SENHA_LOGIN
        )

        if campo_senha is not None:
            return True

        url = page.url.lower()

        marcadores_url = [
            "promobid.promob.com",
            "identity.promob.com",
            "/authentications/signin",
            "/signin",
            "/login",
        ]

        for marcador in marcadores_url:

            if marcador in url:
                return True

    except Exception:
        pass

    return False


# ================================================================
# LOGIN - PREENCHIMENTO AUTOMÁTICO
# ================================================================

async def tentar_login_automatico(
    page,
    email,
    senha
):
    """
    Tenta realizar uma única autenticação automática.

    Retorna:
        True  = login confirmado.
        False = não confirmado.

    IMPORTANTE:
    Não registra a senha em hipótese alguma.
    """

    email = str(
        email or ""
    ).strip()

    senha = str(
        senha or ""
    )

    if not email or not senha:

        log(
            "Credenciais automáticas não disponíveis."
        )

        return False

    log("")
    log("=" * 70)
    log("TENTATIVA DE LOGIN AUTOMÁTICO NO PROMOB ID")
    log("=" * 70)

    log(
        "Credenciais armazenadas: SIM"
    )

    log(
        "E-mail disponível para autenticação: SIM"
    )

    log(
        "Senha disponível para autenticação: SIM"
    )

    # ============================================================
    # LOCALIZAR E-MAIL
    # ============================================================

    campo_email = await localizar_primeiro_visivel(
        page,
        SELETORES_EMAIL_LOGIN
    )

    if campo_email is None:

        log(
            "Campo de e-mail do Promob ID ainda não foi encontrado."
        )

        return False

    # ============================================================
    # LOCALIZAR SENHA
    # ============================================================

    campo_senha = await localizar_primeiro_visivel(
        page,
        SELETORES_SENHA_LOGIN
    )

    if campo_senha is None:

        log(
            "Campo de senha do Promob ID ainda não foi encontrado."
        )

        return False

    # ============================================================
    # PREENCHER E-MAIL
    # ============================================================

    try:

        await campo_email.fill(
            email
        )

        log(
            "E-mail preenchido automaticamente."
        )

    except Exception as e:

        log(
            f"Erro preenchendo e-mail do Promob ID: {e}"
        )

        return False

    # ============================================================
    # PREENCHER SENHA
    # ============================================================

    try:

        await campo_senha.fill(
            senha
        )

        log(
            "Senha preenchida automaticamente."
        )

    except Exception as e:

        log(
            f"Erro preenchendo senha do Promob ID: {e}"
        )

        return False

    # ============================================================
    # LOCALIZAR BOTÃO ENTRAR
    # ============================================================

    botao_entrar = await localizar_primeiro_visivel(
        page,
        SELETORES_ENTRAR_LOGIN
    )

    if botao_entrar is None:

        log(
            "Botão 'Entrar' não foi localizado."
        )

        # ========================================================
        # FALLBACK: ENTER NA SENHA
        # ========================================================

        try:

            await campo_senha.press(
                "Enter"
            )

            log(
                "Tecla ENTER enviada pelo campo de senha."
            )

        except Exception as e:

            log(
                f"Erro enviando ENTER no campo de senha: {e}"
            )

            return False

    else:

        # ========================================================
        # CLIQUE EM ENTRAR
        # ========================================================

        try:

            await botao_entrar.click(
                force=True,
                timeout=10000
            )

            log(
                "Botão 'Entrar' acionado automaticamente."
            )

        except Exception as e:

            log(
                f"Erro clicando em 'Entrar': {e}"
            )

            return False

    # ============================================================
    # AGUARDAR LOGIN
    # ============================================================

    log(
        "Aguardando confirmação do login automático..."
    )

    inicio = asyncio.get_event_loop().time()

    timeout = 30

    while True:

        agora = asyncio.get_event_loop().time()

        if agora - inicio >= timeout:
            break

        try:

            if await login_confirmado(page):

                log("")
                log("=" * 70)
                log("LOGIN AUTOMÁTICO CONFIRMADO")
                log("=" * 70)

                return True

        except Exception:
            pass

        await asyncio.sleep(
            0.5
        )

    # ============================================================
    # RESULTADO
    # ============================================================

    log("")
    log(
        "LOGIN AUTOMÁTICO NÃO FOI CONFIRMADO "
        "dentro do tempo esperado."
    )

    log(
        "O usuário poderá concluir o login manualmente."
    )

    return False


# ================================================================
# LOGIN
# ================================================================

async def esperar_login(
    page,
    email="",
    senha=""
):

    log(
        "Aguardando login do E-Desk..."
    )

    inicio = asyncio.get_event_loop().time()

    timeout = 300

    tentativa_login_automatica = False
    ultimo_log_login = 0.0

    while True:

        agora = asyncio.get_event_loop().time()

        # ========================================================
        # TIMEOUT
        # ========================================================

        if agora - inicio >= timeout:

            raise Exception(
                "Tempo limite aguardando login no E-Desk."
            )

        # ========================================================
        # LOGIN JÁ CONFIRMADO
        # ========================================================

        try:

            if await login_confirmado(page):

                log(
                    "Login confirmado."
                )

                return True

        except Exception:
            pass

        # ========================================================
        # LOGIN AUTOMÁTICO
        # ========================================================

        if (
            not tentativa_login_automatica
            and email
            and senha
        ):

            try:

                formulario_login = await tela_login_detectada(
                    page
                )

            except Exception:
                formulario_login = False

            if formulario_login:

                tentativa_login_automatica = True

                log("")
                log("=" * 70)
                log("TELA DE LOGIN DETECTADA")
                log("=" * 70)

                sucesso = False

                try:

                    sucesso = await tentar_login_automatico(
                        page,
                        email,
                        senha
                    )

                except Exception as e:

                    log(
                        f"Erro durante tentativa de login automático: {e}"
                    )

                if sucesso:

                    return True

                log(
                    "A autenticação automática não foi confirmada."
                )

                log(
                    "Aguardando possibilidade de login manual."
                )

        # ========================================================
        # LOG DE ACOMPANHAMENTO
        # ========================================================

        if agora - ultimo_log_login >= 5:

            try:

                url_atual = page.url

            except Exception:

                url_atual = ""

            log(
                "Aguardando autenticação | "
                f"url={url_atual}"
            )

            ultimo_log_login = agora

        await asyncio.sleep(
            1
        )


# ================================================================
# MINHA GRID
# ================================================================

async def abrir_minha_grid(page):

    log("")
    log("=" * 70)
    log("ABRINDO MINHA GRID")
    log("=" * 70)

    if "ListaSolicitacao.aspx" in page.url:

        log(
            "Página atual já é a Minha Grid."
        )

        return page

    seletores = [
        "text=Minha Grid",
        "a:has-text('Minha Grid')",
        "span:has-text('Minha Grid')",
        "input[value*='Minha Grid']",
        "#cph1_BtMinhasGrid",
    ]

    for seletor in seletores:

        try:

            loc = page.locator(
                seletor
            ).first

            if await loc.count() == 0:
                continue

            if not await loc.is_visible():
                continue

            log(
                f"Minha Grid encontrada por: {seletor}"
            )

            await loc.click(
                force=True
            )

            await asyncio.sleep(2)

            if "ListaSolicitacao.aspx" in page.url:

                log(
                    f"Minha Grid aberta: {page.url}"
                )

                return page

        except Exception:
            continue

    for p in page.context.pages:

        try:

            if p.is_closed():
                continue

            if "ListaSolicitacao.aspx" in p.url:

                log(
                    f"Minha Grid encontrada em outra página: {p.url}"
                )

                return p

        except Exception:
            continue

    raise Exception(
        "Não foi possível abrir/localizar a Minha Grid."
    )


# ================================================================
# FECHAR SOLICITAÇÕES ANTIGAS
# ================================================================

async def fechar_solicitacoes_antigas(
    context,
    manter=None
):

    log("")
    log("=" * 70)
    log("LIMPANDO SOLICITAÇÕES ANTIGAS")
    log("=" * 70)

    paginas = list(
        context.pages
    )

    fechadas = 0

    for p in paginas:

        try:

            if p.is_closed():
                continue

            if manter is not None and p == manter:
                continue

            url = p.url

            if "/Portal/Solicitacao.aspx" in url:

                log(
                    f"Fechando Solicitação antiga: {url}"
                )

                await p.close()

                fechadas += 1

        except Exception as e:

            log(
                f"Erro fechando página antiga: {e}"
            )

    log(
        f"Solicitações antigas fechadas: {fechadas}"
    )

    await asyncio.sleep(0.5)


# ================================================================
# ENCONTRAR SOLICITAÇÃO
# ================================================================

async def pesquisar_solicitacao(
    page,
    solicitacao
):
    numero_solicitacao = somente_numeros(
        solicitacao
    )

    if not numero_solicitacao:
        raise Exception(
            "Número da solicitação não informado."
        )

    log("")
    log("=" * 70)
    log(
        f"PESQUISANDO SOLICITAÇÃO: {solicitacao}"
    )
    log("=" * 70)

    # ============================================================
    # FECHAR SOLICITAÇÕES ANTIGAS
    # ============================================================

    await fechar_solicitacoes_antigas(
        page.context,
        manter=page
    )

    # ============================================================
    # CAMPO DE PESQUISA
    # ============================================================

    campo = page.locator(
        "#cph1_txtSol"
    ).first

    if await campo.count() == 0:
        raise Exception(
            "Campo #cph1_txtSol não encontrado."
        )

    await campo.wait_for(
        state="visible",
        timeout=15000
    )

    await campo.fill("")

    await campo.fill(
        str(solicitacao)
    )

    log(
        "Número da solicitação preenchido."
    )

    # ============================================================
    # BOTÃO PESQUISAR
    # ============================================================

    botao = page.locator(
        "#cph1_btnLocSol"
    ).first

    if await botao.count() == 0:
        raise Exception(
            "Botão #cph1_btnLocSol não encontrado."
        )

    paginas_antes_pesquisa = list(
        page.context.pages
    )

    try:

        await botao.click(
            force=True,
            timeout=10000
        )

    except Exception:

        await campo.press(
            "Enter"
        )

    log(
        "Pesquisa executada."
    )

    # ============================================================
    # AGUARDAR RESULTADO DA GRID
    # ============================================================

    seletor_tabela = (
        "#ctl00_cph1_hgrSol_ctl00"
    )

    tabela = page.locator(
        seletor_tabela
    ).first

    inicio = asyncio.get_event_loop().time()

    while True:

        agora = asyncio.get_event_loop().time()

        if agora - inicio >= 20:
            break

        # --------------------------------------------------------
        # PRIMEIRO VERIFICA SE O E-DESK JÁ ABRIU A SOLICITAÇÃO
        # --------------------------------------------------------

        for p in list(page.context.pages):

            try:

                if p.is_closed():
                    continue

                url_pagina = p.url

                if "/Portal/Solicitacao.aspx" not in url_pagina:
                    continue

                # Confirma também pelo conteúdo da página.
                numero_encontrado = False

                try:

                    body_text = await p.locator(
                        "body"
                    ).inner_text(
                        timeout=2000
                    )

                    if numero_solicitacao in body_text:
                        numero_encontrado = True

                except Exception:
                    pass

                # Se existe somente uma solicitação aberta após a
                # pesquisa, também podemos considerá-la candidata.
                if (
                    numero_encontrado
                    or p not in paginas_antes_pesquisa
                ):

                    log("")
                    log("=" * 70)
                    log(
                        "SOLICITAÇÃO JÁ ABERTA PELO E-DESK"
                    )
                    log("=" * 70)

                    log(
                        f"URL encontrada: {url_pagina}"
                    )

                    try:

                        await p.wait_for_load_state(
                            "domcontentloaded",
                            timeout=10000
                        )

                    except Exception:
                        pass

                    await asyncio.sleep(1)

                    return p

            except Exception:
                continue

        # --------------------------------------------------------
        # VERIFICAR GRID
        # --------------------------------------------------------

        try:

            if await tabela.count() > 0:

                texto_tabela = await tabela.inner_text(
                    timeout=2000
                )

                if numero_solicitacao in texto_tabela:
                    break

        except Exception:
            pass

        await asyncio.sleep(
            0.4
        )

    # ============================================================
    # LINHAS NORMAIS DA TELERIK GRID
    # ============================================================

    seletor_linhas = (
        f"{seletor_tabela} tr.rgRow, "
        f"{seletor_tabela} tr.rgAltRow"
    )

    linhas = page.locator(
        seletor_linhas
    )

    quantidade = await linhas.count()

    log(
        f"Linhas encontradas: {quantidade}"
    )

    linha_encontrada = None

    # ============================================================
    # PROCURA EXATA CÉLULA POR CÉLULA
    # ============================================================

    for i in range(quantidade):

        linha = linhas.nth(i)

        try:

            texto_linha = (
                await linha.inner_text(
                    timeout=2000
                )
            ).strip()

        except Exception:
            continue

        log(
            f"Linha #{i + 1}: "
            f"{re.sub(r'\\s+', ' ', texto_linha)[:500]}"
        )

        celulas = linha.locator(
            "td"
        )

        quantidade_celulas = await celulas.count()

        encontrou_na_celula = False

        for j in range(quantidade_celulas):

            try:

                texto_celula = (
                    await celulas.nth(j).inner_text(
                        timeout=1000
                    )
                ).strip()

            except Exception:
                continue

            numero_celula = somente_numeros(
                texto_celula
            )

            # ----------------------------------------------------
            # COMPARAÇÃO EXATA
            #
            # Não concatena mais todos os números da linha.
            # ----------------------------------------------------

            if numero_celula == numero_solicitacao:

                encontrou_na_celula = True

                log(
                    f"Solicitação encontrada "
                    f"na célula #{j + 1} da linha #{i + 1}."
                )

                break

        if encontrou_na_celula:

            linha_encontrada = linha

            log("")
            log("=" * 70)
            log(
                f"SOLICITAÇÃO ENCONTRADA NA LINHA #{i + 1}"
            )
            log("=" * 70)

            log(
                f"Texto da linha: {texto_linha[:500]}"
            )

            break

    # ============================================================
    # FALLBACK:
    # PROCURA EM TODOS OS TR DA TABELA
    # ============================================================

    if linha_encontrada is None:

        log(
            "Solicitação não encontrada em rgRow/rgAltRow. "
            "Executando fallback em todos os TRs."
        )

        todas_linhas = page.locator(
            f"{seletor_tabela} tr"
        )

        quantidade_todas = await todas_linhas.count()

        log(
            f"Total de TRs para fallback: {quantidade_todas}"
        )

        for i in range(quantidade_todas):

            linha = todas_linhas.nth(i)

            try:

                classe = (
                    await linha.get_attribute(
                        "class"
                    )
                    or ""
                ).lower()

                # Ignora cabeçalhos/filtros.
                if (
                    "rgheader" in classe
                    or "rggroupheader" in classe
                    or "rgfilterrow" in classe
                ):
                    continue

                texto_linha = (
                    await linha.inner_text(
                        timeout=1500
                    )
                ).strip()

            except Exception:
                continue

            if numero_solicitacao not in texto_linha:
                continue

            celulas = linha.locator(
                "td"
            )

            quantidade_celulas = await celulas.count()

            for j in range(quantidade_celulas):

                try:

                    texto_celula = (
                        await celulas.nth(j).inner_text(
                            timeout=800
                        )
                    ).strip()

                except Exception:
                    continue

                numero_celula = somente_numeros(
                    texto_celula
                )

                if numero_celula == numero_solicitacao:

                    linha_encontrada = linha

                    log("")
                    log("=" * 70)
                    log(
                        "SOLICITAÇÃO ENCONTRADA PELO FALLBACK"
                    )
                    log("=" * 70)

                    log(
                        f"Linha fallback #{i + 1}: "
                        f"{texto_linha[:500]}"
                    )

                    break

            if linha_encontrada is not None:
                break

    # ============================================================
    # ÚLTIMA VERIFICAÇÃO:
    # TALVEZ A SOLICITAÇÃO TENHA SIDO ABERTA DURANTE A BUSCA
    # ============================================================

    if linha_encontrada is None:

        for p in list(page.context.pages):

            try:

                if p.is_closed():
                    continue

                if "/Portal/Solicitacao.aspx" not in p.url:
                    continue

                texto_pagina = ""

                try:

                    texto_pagina = await p.locator(
                        "body"
                    ).inner_text(
                        timeout=2000
                    )

                except Exception:
                    pass

                if numero_solicitacao in texto_pagina:

                    log("")
                    log("=" * 70)
                    log(
                        "SOLICITAÇÃO LOCALIZADA EM OUTRA ABA"
                    )
                    log("=" * 70)

                    log(
                        f"URL: {p.url}"
                    )

                    try:

                        await p.wait_for_load_state(
                            "domcontentloaded",
                            timeout=10000
                        )

                    except Exception:
                        pass

                    await asyncio.sleep(1)

                    return p

            except Exception:
                continue

        raise Exception(
            f"Solicitação {solicitacao} "
            "não encontrada na Minha Grid."
        )

    # ============================================================
    # ABERTURA DA SOLICITAÇÃO
    # ============================================================

    log("")
    log("=" * 70)
    log(
        "ABRINDO SOLICITAÇÃO - ÚNICO DBLCLICK"
    )
    log("=" * 70)

    log(
        f"URL antes do dblclick: {page.url}"
    )

    paginas_antes = list(
        page.context.pages
    )

    log(
        f"Páginas antes do dblclick: "
        f"{len(paginas_antes)}"
    )

    for i, p in enumerate(
        paginas_antes,
        start=1
    ):

        try:

            log(
                f"  Antes #{i}: {p.url}"
            )

        except Exception:
            pass

    # ============================================================
    # DBLCLICK ÚNICO
    # ============================================================

    await linha_encontrada.dblclick(
        force=True,
        timeout=10000
    )

    log(
        "ÚNICO dblclick executado."
    )

    log(
        "Aguardando abertura da Solicitação.aspx..."
    )

    # ============================================================
    # LOCALIZAR A PÁGINA DA SOLICITAÇÃO
    # ============================================================

    pagina_solicitacao = None

    inicio = asyncio.get_event_loop().time()

    timeout = 30

    paginas_logadas = set()

    while True:

        agora = asyncio.get_event_loop().time()

        if agora - inicio >= timeout:
            break

        paginas = list(
            page.context.pages
        )

        for p in paginas:

            try:

                if p.is_closed():
                    continue

                url_pagina = p.url

                if p not in paginas_antes:

                    chave = (
                        f"nova:{id(p)}:{url_pagina}"
                    )

                    if chave not in paginas_logadas:

                        log(
                            f"NOVA página detectada: "
                            f"{url_pagina}"
                        )

                        paginas_logadas.add(
                            chave
                        )

                if "/Portal/Solicitacao.aspx" not in url_pagina:
                    continue

                # ------------------------------------------------
                # CONFIRMA QUE É A SOLICITAÇÃO CORRETA
                # ------------------------------------------------

                correta = False

                try:

                    texto_pagina = await p.locator(
                        "body"
                    ).inner_text(
                        timeout=1500
                    )

                    correta = (
                        numero_solicitacao
                        in texto_pagina
                    )

                except Exception:

                    # Página acabou de abrir e o DOM ainda não está
                    # disponível. Se for página nova, aguarda abaixo.
                    correta = (
                        p not in paginas_antes
                    )

                if correta:

                    pagina_solicitacao = p
                    break

            except Exception:
                continue

        if pagina_solicitacao is not None:
            break

        # --------------------------------------------------------
        # ALGUNS FLUXOS NAVEGAM NA MESMA ABA
        # --------------------------------------------------------

        try:

            if (
                "/Portal/Solicitacao.aspx"
                in page.url
            ):

                pagina_solicitacao = page
                break

        except Exception:
            pass

        await asyncio.sleep(
            0.2
        )

    # ============================================================
    # LOG DAS PÁGINAS
    # ============================================================

    log("")
    log(
        "Páginas existentes após tentativa:"
    )

    paginas_finais = list(
        page.context.pages
    )

    for i, p in enumerate(
        paginas_finais,
        start=1
    ):

        try:

            if p.is_closed():
                continue

            log(
                f"  Página #{i}: {p.url}"
            )

        except Exception:
            pass

    if pagina_solicitacao is None:

        raise Exception(
            "A solicitação foi localizada, mas a "
            "página Solicitação.aspx não foi aberta."
        )

    # ============================================================
    # AGUARDAR CARREGAMENTO
    # ============================================================

    try:

        await pagina_solicitacao.wait_for_load_state(
            "domcontentloaded",
            timeout=10000
        )

    except Exception:
        pass

    await asyncio.sleep(1)

    # ============================================================
    # CONFIRMAÇÃO FINAL
    # ============================================================

    log("")
    log("=" * 70)
    log(
        "SOLICITAÇÃO ABERTA COM SUCESSO"
    )
    log("=" * 70)

    log(
        f"URL da Solicitação: "
        f"{pagina_solicitacao.url}"
    )

    await close_new_duplicate_requests(page.context, pagina_solicitacao, paginas_antes)
    return pagina_solicitacao

# ================================================================
# AUXILIARES DA ABA FASES
# ================================================================

async def obter_client_state_fases(page):

    try:

        campo = page.locator(
            "#ctl00_cph1_rTabSol_ClientState"
        )

        if await campo.count() == 0:
            return ""

        return (
            await campo.input_value()
        )

    except Exception:

        return ""


async def obter_estado_radtabstrip(page):

    estado = await obter_client_state_fases(
        page
    )

    if not estado:
        return {}

    try:

        dados = json.loads(
            estado
        )

        if isinstance(dados, dict):
            return dados

    except Exception:
        pass

    return {}


async def obter_view_fases_info(page):

    """
    Retorna informações da view cph1_rpvFasePro.
    """

    resultado = {
        "existe": False,
        "visivel": False,
        "display": "",
        "visibility": "",
        "classe": "",
        "style": "",
        "texto": "",
        "html_tamanho": 0,
        "inputs": 0,
    }

    try:

        view = page.locator(
            "#cph1_rpvFasePro"
        )

        if await view.count() == 0:
            return resultado

        resultado["existe"] = True

        try:
            resultado["visivel"] = await view.is_visible()
        except Exception:
            resultado["visivel"] = False

        try:

            dados = await view.evaluate(
                """
                (e) => {
                    const s = window.getComputedStyle(e);

                    return {
                        display: s.display || "",
                        visibility: s.visibility || "",
                        classe: e.className || "",
                        style: e.getAttribute("style") || "",
                        html_tamanho: e.innerHTML
                            ? e.innerHTML.length
                            : 0
                    };
                }
                """
            )

            if isinstance(dados, dict):

                resultado["display"] = (
                    dados.get("display") or ""
                )

                resultado["visibility"] = (
                    dados.get("visibility") or ""
                )

                resultado["classe"] = (
                    dados.get("classe") or ""
                )

                resultado["style"] = (
                    dados.get("style") or ""
                )

                resultado["html_tamanho"] = (
                    dados.get("html_tamanho") or 0
                )

        except Exception:
            pass

        try:

            resultado["texto"] = (
                await view.inner_text(
                    timeout=500
                )
            ).strip()

        except Exception:
            resultado["texto"] = ""

        try:

            resultado["inputs"] = await view.locator(
                "input"
            ).count()

        except Exception:
            resultado["inputs"] = 0

    except Exception:
        pass

    return resultado


async def salvar_diagnostico_html(page, motivo=""):

    try:

        html = await page.content()

        with open(
            DIAGNOSTICO_HTML,
            "w",
            encoding="utf-8"
        ) as arquivo:

            arquivo.write(
                html
            )

        log(
            f"HTML de diagnóstico salvo em: "
            f"{DIAGNOSTICO_HTML}"
        )

        if motivo:

            log(
                f"Motivo do diagnóstico: {motivo}"
            )

        return True

    except Exception as e:

        log(
            f"Erro salvando diagnóstico HTML: {e}"
        )

        return False


# ================================================================
# ABRIR A ABA FASES CORRETA
# ================================================================

async def abrir_fases(page):

    log("")
    log("=" * 70)
    log("ABRINDO ABA FASES DA BARRA PRINCIPAL")
    log("=" * 70)

    try:

        # ============================================================
        # ESTADO ANTES DO CLIQUE
        # ============================================================

        estado_antes = await obter_client_state_fases(
            page
        )

        log(
            f"ClientState antes do clique: "
            f"{estado_antes}"
        )

        info_antes = await obter_view_fases_info(
            page
        )

        log(
            "View Fases antes do clique: "
            f"existe={info_antes['existe']} | "
            f"visivel={info_antes['visivel']} | "
            f"display={info_antes['display']} | "
            f"visibility={info_antes['visibility']} | "
            f"classe={info_antes['classe']} | "
            f"inputs={info_antes['inputs']} | "
            f"html={info_antes['html_tamanho']}"
        )

        assinatura_antes = (
            info_antes["style"],
            info_antes["classe"],
            info_antes["html_tamanho"],
            info_antes["texto"][:1000],
        )

        # ============================================================
        # LOCALIZAR EXATAMENTE A ABA "Fases"
        # ============================================================

        aba_fases = page.locator(
            "div.rtsLevel.rtsLevel1 "
            "ul.rtsUL "
            "li.rtsLI "
            "a.rtsLink"
        ).filter(
            has=page.locator(
                "span.rtsTxt"
            ).filter(
                has_text=re.compile(
                    r"^\s*Fases\s*$",
                    re.IGNORECASE
                )
            )
        ).first

        if await aba_fases.count() == 0:

            log(
                "Filtro exato não encontrou a aba. "
                "Tentando localizar pelo texto."
            )

            textos = page.locator(
                "div.rtsLevel.rtsLevel1 "
                "ul.rtsUL "
                "li.rtsLI "
                "a.rtsLink "
                "span.rtsTxt"
            )

            quantidade = await textos.count()

            log(
                f"Textos de abas encontrados: {quantidade}"
            )

            for i in range(quantidade):

                try:

                    texto = (
                        await textos.nth(i).inner_text()
                    ).strip()

                    log(
                        f"  Aba [{i}]: {texto}"
                    )

                    if normalizar(texto) == "fases":

                        aba_fases = textos.nth(i).locator(
                            "xpath=ancestor::a[1]"
                        )

                        break

                except Exception:
                    continue

        if await aba_fases.count() == 0:

            log(
                "ERRO: Aba 'Fases' não encontrada."
            )

            return False

        texto_aba = ""

        try:

            texto_aba = (
                await aba_fases.locator(
                    "span.rtsTxt"
                ).inner_text()
            ).strip()

        except Exception:
            pass

        log(
            f"Aba encontrada: {texto_aba or 'Fases'}"
        )

        # ============================================================
        # CONFIRMAR BARRA PRINCIPAL
        # ============================================================

        barra_principal = aba_fases.locator(
            "xpath=ancestor::div[contains(@class,'rtsLevel1')]"
        )

        if await barra_principal.count() == 0:

            log(
                "ERRO: Aba Fases não pertence à barra principal."
            )

            return False

        log(
            "Elemento confirmado dentro da barra principal."
        )

        # ============================================================
        # IDENTIFICAR ÍNDICE
        # ============================================================

        try:

            indice_aba = await aba_fases.evaluate(
                """
                (el) => {
                    const li = el.closest("li.rtsLI");

                    if (!li || !li.parentElement) {
                        return -1;
                    }

                    return Array.from(
                        li.parentElement.children
                    ).indexOf(li);
                }
                """
            )

            log(
                f"Índice da aba Fases encontrado no DOM: "
                f"{indice_aba}"
            )

        except Exception:

            indice_aba = -1

        if indice_aba != 2:

            log(
                "AVISO: o índice encontrado para Fases "
                f"foi {indice_aba}; esperado: 2."
            )

        # ============================================================
        # CLIQUE
        # ============================================================

        log(
            "Clicando na aba Fases..."
        )

        await aba_fases.click(
            force=True,
            timeout=10000
        )

        log(
            "Clique na aba Fases realizado."
        )

        # ============================================================
        # AGUARDAR AJAX / TELERIK
        # ============================================================

        log(
            "Aguardando atualização AJAX/Telerik..."
        )

        inicio = asyncio.get_event_loop().time()

        timeout = 20

        fase_carregada = False
        confirmou_indice = False
        confirmou_view_visivel = False
        confirmou_conteudo = False

        ultimo_log = 0.0

        nomes_esperados = [
            "gerenciamento de projetos",
            "contato inicial",
            "levantamento de escopo",
            "desenvolvimento",
            "implantacao",
            "pos implantacao",
        ]

        while True:

            agora = asyncio.get_event_loop().time()

            if agora - inicio >= timeout:
                break

            try:

                # ----------------------------------------------------
                # CLIENT STATE
                # ----------------------------------------------------

                estado = await obter_client_state_fases(
                    page
                )

                selecionada_2 = False

                if estado:

                    try:

                        dados_estado = json.loads(
                            estado
                        )

                        selecionados = (
                            dados_estado.get(
                                "selectedIndexes",
                                []
                            )
                        )

                        selecionada_2 = (
                            "2" in selecionados
                            or 2 in selecionados
                        )

                    except Exception:
                        pass

                if selecionada_2:

                    if not confirmou_indice:

                        log(
                            "RadTabStrip confirmou "
                            "selectedIndexes contendo [2]."
                        )

                    confirmou_indice = True

                # ----------------------------------------------------
                # VIEW
                # ----------------------------------------------------

                info_view = await obter_view_fases_info(
                    page
                )

                existe_view = info_view["existe"]
                visivel_view = info_view["visivel"]

                if existe_view and visivel_view:

                    if not confirmou_view_visivel:

                        log(
                            "View cph1_rpvFasePro "
                            "ficou VISÍVEL."
                        )

                    confirmou_view_visivel = True

                # ----------------------------------------------------
                # MUDANÇA REAL
                # ----------------------------------------------------

                assinatura_atual = (
                    info_view["style"],
                    info_view["classe"],
                    info_view["html_tamanho"],
                    info_view["texto"][:1000],
                )

                view_mudou = (
                    assinatura_atual != assinatura_antes
                )

                # ----------------------------------------------------
                # NOMES DAS FASES
                # ----------------------------------------------------

                texto_view_normalizado = normalizar(
                    info_view["texto"]
                )

                quantidade_nomes = 0

                for nome_esperado in nomes_esperados:

                    if nome_esperado in texto_view_normalizado:

                        quantidade_nomes += 1

                if quantidade_nomes > 0:

                    if not confirmou_conteudo:

                        log(
                            "Conteúdo de fases detectado "
                            f"na view: {quantidade_nomes} "
                            "nome(s) conhecido(s)."
                        )

                    confirmou_conteudo = True

                # ----------------------------------------------------
                # LOG
                # ----------------------------------------------------

                tempo_decorrido = agora - ultimo_log

                if tempo_decorrido >= 1.0:

                    log(
                        "Aguardando Fases | "
                        f"selectedIndex2={selecionada_2} | "
                        f"viewExiste={existe_view} | "
                        f"viewVisivel={visivel_view} | "
                        f"viewMudou={view_mudou} | "
                        f"inputs={info_view['inputs']} | "
                        f"html={info_view['html_tamanho']} | "
                        f"nomes={quantidade_nomes}"
                    )

                    ultimo_log = agora

                # ----------------------------------------------------
                # SUCESSO
                # ----------------------------------------------------

                if (
                    confirmou_indice
                    and confirmou_view_visivel
                    and confirmou_conteudo
                ):

                    fase_carregada = True

                    log(
                        "Condição completa confirmada."
                    )

                    break

                # ----------------------------------------------------
                # FALLBACK
                # ----------------------------------------------------

                if (
                    confirmou_indice
                    and confirmou_view_visivel
                    and view_mudou
                    and (
                        info_view["inputs"] > 0
                        or info_view["html_tamanho"] > 0
                    )
                ):

                    fase_carregada = True

                    log(
                        "View Fases confirmada por alteração "
                        "real do conteúdo após o AJAX."
                    )

                    break

            except Exception as e:

                log(
                    f"Aguardando Fases: {e}"
                )

            await asyncio.sleep(
                0.25
            )

        # ============================================================
        # RESULTADO
        # ============================================================

        if fase_carregada:

            log("")
            log("=" * 70)
            log("ABA FASES CARREGADA COM SUCESSO")
            log("=" * 70)

            estado_final = await obter_client_state_fases(
                page
            )

            log(
                f"ClientState após carregamento: "
                f"{estado_final}"
            )

            info_final = await obter_view_fases_info(
                page
            )

            log(
                "View final: "
                f"visivel={info_final['visivel']} | "
                f"display={info_final['display']} | "
                f"visibility={info_final['visibility']} | "
                f"classe={info_final['classe']} | "
                f"inputs={info_final['inputs']} | "
                f"html={info_final['html_tamanho']}"
            )

            texto_fases = re.sub(
                r"\s+",
                " ",
                info_final["texto"]
            ).strip()

            log(
                f"Texto da view Fases "
                f"({len(texto_fases)} caracteres):"
            )

            log(
                texto_fases[:5000]
            )

            return True

        # ============================================================
        # FALHA
        # ============================================================

        log("")
        log("=" * 70)
        log(
            "AVISO: clique executado, mas a aba Fases "
            "não pôde ser confirmada."
        )
        log("=" * 70)

        estado_final = await obter_client_state_fases(
            page
        )

        log(
            f"ClientState final: {estado_final}"
        )

        info_final = await obter_view_fases_info(
            page
        )

        log(
            "View final: "
            f"existe={info_final['existe']} | "
            f"visivel={info_final['visivel']} | "
            f"display={info_final['display']} | "
            f"visibility={info_final['visibility']} | "
            f"classe={info_final['classe']} | "
            f"inputs={info_final['inputs']} | "
            f"html={info_final['html_tamanho']}"
        )

        await salvar_diagnostico_html(
            page,
            motivo=(
                "Aba Fases clicada, mas "
                "cph1_rpvFasePro não foi confirmada."
            )
        )

        return False

    except Exception as e:

        log(
            f"ERRO ao abrir a aba Fases: {e}"
        )

        await salvar_diagnostico_html(
            page,
            motivo=f"Exceção ao abrir Fases: {e}"
        )

        return False


# ================================================================
# DIAGNÓSTICO COMPLETO
# ================================================================

async def diagnosticar_fases(page):

    log("")
    log("=" * 70)
    log("DIAGNÓSTICO PROFUNDO DO CONTEÚDO DE FASES")
    log("=" * 70)

    log(
        f"URL atual: {page.url}"
    )

    # ============================================================
    # RADTABSTRIP
    # ============================================================

    log("")
    log("-" * 70)
    log("ESTADO DO RADTABSTRIP")
    log("-" * 70)

    try:

        estado = await obter_client_state_fases(
            page
        )

        log(
            f"ClientState: {estado}"
        )

        dados_estado = await obter_estado_radtabstrip(
            page
        )

        log(
            f"Estado interpretado: {dados_estado}"
        )

    except Exception as e:

        log(
            f"Erro lendo ClientState: {e}"
        )

    # ============================================================
    # VIEW
    # ============================================================

    log("")
    log("-" * 70)
    log("VIEW cph1_rpvFasePro")
    log("-" * 70)

    try:

        info = await obter_view_fases_info(
            page
        )

        log(
            f"Existe: {info['existe']}"
        )

        log(
            f"Visível: {info['visivel']}"
        )

        log(
            f"Display: {info['display']}"
        )

        log(
            f"Visibility: {info['visibility']}"
        )

        log(
            f"Classe: {info['classe']}"
        )

        log(
            f"Style: {info['style']}"
        )

        log(
            f"Inputs: {info['inputs']}"
        )

        log(
            f"Tamanho HTML: {info['html_tamanho']}"
        )

        texto_view = re.sub(
            r"\s+",
            " ",
            info["texto"]
        ).strip()

        log(
            f"Texto da view: {texto_view[:5000]}"
        )

    except Exception as e:

        log(
            f"Erro diagnosticando view Fases: {e}"
        )

    # ============================================================
    # FRAMES
    # ============================================================

    log("")
    log("-" * 70)
    log("FRAMES EXISTENTES")
    log("-" * 70)

    try:

        frames = page.frames

        log(
            f"Quantidade de frames: {len(frames)}"
        )

        for i, frame in enumerate(
            frames
        ):

            try:

                log(
                    f"FRAME {i} | url={frame.url}"
                )

            except Exception:
                pass

    except Exception as e:

        log(
            f"Erro diagnosticando frames: {e}"
        )

    # ============================================================
    # TEXTO VISÍVEL
    # ============================================================

    log("")
    log("-" * 70)
    log("TEXTO VISÍVEL DA PÁGINA")
    log("-" * 70)

    try:

        texto_body = await page.locator(
            "body"
        ).inner_text(
            timeout=3000
        )

        texto_body = re.sub(
            r"\s+",
            " ",
            texto_body
        ).strip()

        log(
            f"Tamanho do texto visível: "
            f"{len(texto_body)} caracteres"
        )

        nomes_procurados = [
            "Gerenciamento de Projetos",
            "Contato Inicial",
            "Levantamento de Escopo",
            "Desenvolvimento",
            "Implantação",
            "Pós Implantação",
        ]

        texto_normalizado = normalizar(
            texto_body
        )

        for nome in nomes_procurados:

            if normalizar(nome) in texto_normalizado:

                log(
                    f"TEXTO ENCONTRADO: {nome}"
                )

            else:

                log(
                    f"TEXTO NÃO ENCONTRADO: {nome}"
                )

        posicao = texto_normalizado.find(
            "fase"
        )

        if posicao >= 0:

            inicio = max(
                0,
                posicao - 500
            )

            fim = min(
                len(texto_body),
                posicao + 2500
            )

            log(
                "TRECHO PRÓXIMO À PALAVRA 'FASE':"
            )

            log(
                texto_body[inicio:fim]
            )

    except Exception as e:

        log(
            f"Erro lendo texto da página: {e}"
        )

    # ============================================================
    # ELEMENTOS FASES
    # ============================================================

    log("")
    log("-" * 70)
    log("ELEMENTOS CONTENDO NOMES DAS FASES")
    log("-" * 70)

    nomes_procurados = [
        "Gerenciamento de Projetos",
        "Contato Inicial",
        "Levantamento de Escopo",
        "Desenvolvimento",
        "Implantação",
        "Pós Implantação",
    ]

    for nome in nomes_procurados:

        try:

            loc = page.get_by_text(
                nome,
                exact=False
            )

            qtd = await loc.count()

            log(
                f"'{nome}' -> {qtd} elemento(s)"
            )

            for i in range(
                min(qtd, 10)
            ):

                try:

                    el = loc.nth(i)

                    tag = await el.evaluate(
                        "(e) => e.tagName"
                    )

                    id_el = await el.get_attribute(
                        "id"
                    )

                    classe = await el.get_attribute(
                        "class"
                    )

                    log(
                        f"  [{i}] "
                        f"tag={tag} "
                        f"id={id_el} "
                        f"class={classe}"
                    )

                except Exception:
                    pass

        except Exception as e:

            log(
                f"Erro procurando '{nome}': {e}"
            )

    # ============================================================
    # INPUTS
    # ============================================================

    log("")
    log("-" * 70)
    log("TODOS OS INPUTS")
    log("-" * 70)

    try:

        todos_inputs = page.locator(
            "input"
        )

        qtd_inputs = await todos_inputs.count()

        log(
            f"Total de inputs: {qtd_inputs}"
        )

        for i in range(
            min(qtd_inputs, 250)
        ):

            try:

                inp = todos_inputs.nth(i)

                id_input = await inp.get_attribute(
                    "id"
                )

                name_input = await inp.get_attribute(
                    "name"
                )

                type_input = await inp.get_attribute(
                    "type"
                )

                value_input = ""

                try:

                    value_input = await inp.input_value()

                except Exception:
                    pass

                classe_input = await inp.get_attribute(
                    "class"
                )

                texto_busca = normalizar(
                    " ".join([
                        str(id_input or ""),
                        str(name_input or ""),
                        str(type_input or ""),
                        str(classe_input or ""),
                        str(value_input or ""),
                    ])
                )

                palavras_interesse = [
                    "fas",
                    "fase",
                    "data",
                    "dt",
                    "inicio",
                    "fim",
                    "ter",
                    "ini",
                    "date",
                ]

                interessante = any(
                    palavra in texto_busca
                    for palavra in palavras_interesse
                )

                if interessante:

                    log(
                        f"INPUT {i} | "
                        f"id={id_input} | "
                        f"name={name_input} | "
                        f"type={type_input} | "
                        f"class={classe_input} | "
                        f"value={value_input}"
                    )

            except Exception:
                pass

    except Exception as e:

        log(
            f"Erro diagnosticando inputs: {e}"
        )

    # ============================================================
    # INPUTS DA VIEW FASES
    # ============================================================

    log("")
    log("-" * 70)
    log("INPUTS DENTRO DE cph1_rpvFasePro")
    log("-" * 70)

    try:

        view = page.locator(
            "#cph1_rpvFasePro"
        )

        if await view.count() > 0:

            inputs_view = view.locator(
                "input"
            )

            qtd_view = await inputs_view.count()

            log(
                f"Inputs dentro da view Fases: {qtd_view}"
            )

            for i in range(
                min(qtd_view, 250)
            ):

                try:

                    inp = inputs_view.nth(i)

                    id_input = await inp.get_attribute(
                        "id"
                    )

                    name_input = await inp.get_attribute(
                        "name"
                    )

                    type_input = await inp.get_attribute(
                        "type"
                    )

                    value_input = ""

                    try:

                        value_input = (
                            await inp.input_value()
                        )

                    except Exception:
                        pass

                    classe_input = await inp.get_attribute(
                        "class"
                    )

                    log(
                        f"VIEW INPUT {i} | "
                        f"id={id_input} | "
                        f"name={name_input} | "
                        f"type={type_input} | "
                        f"class={classe_input} | "
                        f"value={value_input}"
                    )

                except Exception:
                    pass

        else:

            log(
                "View cph1_rpvFasePro não existe."
            )

    except Exception as e:

        log(
            f"Erro diagnosticando inputs da view: {e}"
        )

    # ============================================================
    # SELECTS
    # ============================================================

    log("")
    log("-" * 70)
    log("SELECTS")
    log("-" * 70)

    try:

        selects = page.locator(
            "select"
        )

        qtd_selects = await selects.count()

        log(
            f"Total de selects: {qtd_selects}"
        )

        for i in range(
            min(qtd_selects, 100)
        ):

            try:

                sel = selects.nth(i)

                id_sel = await sel.get_attribute(
                    "id"
                )

                name_sel = await sel.get_attribute(
                    "name"
                )

                classe_sel = await sel.get_attribute(
                    "class"
                )

                log(
                    f"SELECT {i} | "
                    f"id={id_sel} | "
                    f"name={name_sel} | "
                    f"class={classe_sel}"
                )

            except Exception:
                pass

    except Exception as e:

        log(
            f"Erro diagnosticando selects: {e}"
        )

    # ============================================================
    # FAS / FASE
    # ============================================================

    log("")
    log("-" * 70)
    log("ELEMENTOS COM FAS / FASE NO ID OU CLASS")
    log("-" * 70)

    try:

        elementos = page.locator(
            "[id*='Fas'], "
            "[id*='fas'], "
            "[id*='Fase'], "
            "[id*='fase'], "
            "[class*='Fas'], "
            "[class*='fas'], "
            "[class*='Fase'], "
            "[class*='fase']"
        )

        qtd_elementos = await elementos.count()

        log(
            f"Elementos encontrados: "
            f"{qtd_elementos}"
        )

        for i in range(
            min(qtd_elementos, 250)
        ):

            try:

                el = elementos.nth(i)

                tag = await el.evaluate(
                    "(e) => e.tagName"
                )

                id_el = await el.get_attribute(
                    "id"
                )

                classe = await el.get_attribute(
                    "class"
                )

                texto = ""

                try:

                    texto = await el.inner_text(
                        timeout=300
                    )

                    texto = re.sub(
                        r"\s+",
                        " ",
                        texto
                    ).strip()

                except Exception:
                    pass

                log(
                    f"ELEMENTO {i} | "
                    f"tag={tag} | "
                    f"id={id_el} | "
                    f"class={classe} | "
                    f"texto={texto[:300]}"
                )

            except Exception:
                pass

    except Exception as e:

        log(
            f"Erro diagnosticando elementos Fase: {e}"
        )

    # ============================================================
    # TABELAS
    # ============================================================

    log("")
    log("-" * 70)
    log("TABELAS")
    log("-" * 70)

    try:

        tabelas = page.locator(
            "table"
        )

        qtd_tabelas = await tabelas.count()

        log(
            f"Quantidade de tabelas: {qtd_tabelas}"
        )

        for i in range(
            min(qtd_tabelas, 100)
        ):

            try:

                tabela = tabelas.nth(i)

                id_tabela = await tabela.get_attribute(
                    "id"
                )

                classe_tabela = await tabela.get_attribute(
                    "class"
                )

                texto_tabela = ""

                try:

                    texto_tabela = await tabela.inner_text(
                        timeout=300
                    )

                    texto_tabela = re.sub(
                        r"\s+",
                        " ",
                        texto_tabela
                    ).strip()

                except Exception:
                    pass

                texto_tabela_normalizado = normalizar(
                    texto_tabela
                )

                relevante = (
                    "fase" in texto_tabela_normalizado
                    or "gerenciamento" in texto_tabela_normalizado
                    or "levantamento" in texto_tabela_normalizado
                    or "implantacao" in texto_tabela_normalizado
                )

                if relevante:

                    log(
                        f"TABELA {i} | "
                        f"id={id_tabela} | "
                        f"class={classe_tabela}"
                    )

                    log(
                        f"  texto={texto_tabela[:2000]}"
                    )

            except Exception:
                pass

    except Exception as e:

        log(
            f"Erro diagnosticando tabelas: {e}"
        )

    # ============================================================
    # HTML
    # ============================================================

    log("")
    log("-" * 70)
    log("SALVANDO HTML COMPLETO PARA DIAGNÓSTICO")
    log("-" * 70)

    await salvar_diagnostico_html(
        page,
        motivo="Diagnóstico profundo solicitado."
    )

    try:

        if DIAGNOSTICO_HTML.exists():

            tamanho = DIAGNOSTICO_HTML.stat().st_size

            log(
                f"Tamanho do arquivo HTML: {tamanho} bytes"
            )

    except Exception:
        pass

    # ============================================================
    # HTML DOS FRAMES
    # ============================================================

    if len(page.frames) > 1:

        log("")
        log("-" * 70)
        log("DIAGNÓSTICO DOS FRAMES")
        log("-" * 70)

        for i, frame in enumerate(
            page.frames
        ):

            try:

                html_frame = await frame.content()

                arquivo_frame = (
                    LOG_DIR /
                    f"fases_frame_{i}.html"
                )

                with open(
                    arquivo_frame,
                    "w",
                    encoding="utf-8"
                ) as arquivo:

                    arquivo.write(
                        html_frame
                    )

                log(
                    f"FRAME {i} HTML salvo em: "
                    f"{arquivo_frame}"
                )

            except Exception as e:

                log(
                    f"Erro salvando HTML do frame {i}: {e}"
                )

    log("")
    log("=" * 70)
    log("FIM DO DIAGNÓSTICO PROFUNDO")
    log("=" * 70)


# ================================================================
# PREENCHER FASES
#
# IMPORTANTE:
#
# - SOMENTE preenche os campos.
# - NÃO salva.
# - NÃO clica em nenhum botão Salvar.
#
# COLUNAS DO E-DESK:
#
# Dt. Ini. Ajustada
# Dt. Fin. Ajustada
# ================================================================

async def atualizar_fases(
    page,
    fases_flutter
):

    log("")
    log("=" * 70)
    log("PREENCHENDO FASES - SEM SALVAR")
    log("=" * 70)

    log(
        "ATENÇÃO: as datas serão apenas preenchidas na tela."
    )

    log(
        "ATENÇÃO: nenhum botão Salvar será acionado."
    )

    fases_atualizadas = []
    fases_nao_encontradas = []
    erros = []

    try:

        # ============================================================
        # GARANTIR VIEW
        # ============================================================

        view = page.locator(
            "#cph1_rpvFasePro"
        )

        if await view.count() == 0:

            log(
                "View cph1_rpvFasePro não encontrada."
            )

            await diagnosticar_fases(
                page
            )

            return fases_atualizadas

        info_view = await obter_view_fases_info(
            page
        )

        log(
            "View Fases: "
            f"visivel={info_view['visivel']} | "
            f"display={info_view['display']} | "
            f"visibility={info_view['visibility']} | "
            f"inputs={info_view['inputs']} | "
            f"html={info_view['html_tamanho']}"
        )

        if not info_view["visivel"]:

            log(
                "A view Fases existe, mas não está visível."
            )

            await diagnosticar_fases(
                page
            )

            return fases_atualizadas

        # ============================================================
        # FASES DO FLUTTER
        # ============================================================

        fases_recebidas = {}

        if isinstance(
            fases_flutter,
            list
        ):

            for fase_flutter in fases_flutter:

                if not isinstance(
                    fase_flutter,
                    dict
                ):
                    continue

                nome_flutter = str(
                    fase_flutter.get(
                        "nome",
                        ""
                    )
                ).strip()

                if not nome_flutter:
                    continue

                chave = chave_fase(
                    nome_flutter
                )

                fases_recebidas[chave] = {
                    "nome": nome_flutter,
                    "dataInicial": formatar_data(
                        fase_flutter.get(
                            "dataInicial",
                            ""
                        )
                    ),
                    "dataFinal": formatar_data(
                        fase_flutter.get(
                            "dataFinal",
                            ""
                        )
                    ),
                }

                log(
                    f"FLUTTER | "
                    f"{nome_flutter} | "
                    f"Inicial={fases_recebidas[chave]['dataInicial']} | "
                    f"Final={fases_recebidas[chave]['dataFinal']}"
                )

        # ============================================================
        # NOMES DAS FASES NO E-DESK
        # ============================================================

        nomes = view.locator(
            "span[id*='lblGFasNome']"
        )

        qtd_nomes = await nomes.count()

        log(
            f"Elementos de nome de fase encontrados: "
            f"{qtd_nomes}"
        )

        # ============================================================
        # DT. INI. AJUSTADA
        # ============================================================

        datas_inicio = view.locator(
            "input[id*='txtGFasDtIniAj']"
        )

        qtd_inicio = await datas_inicio.count()

        log(
            "Campos 'Dt. Ini. Ajustada' encontrados: "
            f"{qtd_inicio}"
        )

        # ============================================================
        # DT. FIN. AJUSTADA
        # ============================================================

        datas_fim = view.locator(
            "input[id*='txtGFasDtTerAju']"
        )

        qtd_fim = await datas_fim.count()

        log(
            "Campos 'Dt. Fin. Ajustada' encontrados: "
            f"{qtd_fim}"
        )

        # ============================================================
        # VALIDAR ESTRUTURA
        # ============================================================

        if qtd_nomes == 0:

            log(
                "Nenhum nome de fase encontrado."
            )

            await diagnosticar_fases(
                page
            )

            return fases_atualizadas

        if qtd_inicio == 0:

            log(
                "Nenhum campo 'Dt. Ini. Ajustada' encontrado."
            )

            await diagnosticar_fases(
                page
            )

            return fases_atualizadas

        if qtd_fim == 0:

            log(
                "Nenhum campo 'Dt. Fin. Ajustada' encontrado."
            )

            await diagnosticar_fases(
                page
            )

            return fases_atualizadas

        # ============================================================
        # PROCESSAR TODAS AS FASES
        # ============================================================

        quantidade = max(
            qtd_nomes,
            qtd_inicio,
            qtd_fim,
        )

        for i in range(
            quantidade
        ):

            nome_edesk = ""

            if i < qtd_nomes:

                try:

                    nome_edesk = (
                        await nomes.nth(i).inner_text()
                    ).strip()

                except Exception:
                    nome_edesk = ""

            log("")
            log(
                "-" * 70
            )

            log(
                f"PROCESSANDO FASE #{i + 1}"
            )

            log(
                f"Nome E-Desk: {nome_edesk or '(sem nome)'}"
            )

            if not nome_edesk:

                log(
                    "Fase sem nome. Ignorando."
                )

                erros.append({
                    "indice": i + 1,
                    "erro": "Fase sem nome no E-Desk.",
                })

                continue

            chave = chave_fase(
                nome_edesk
            )

            dados_fase = fases_recebidas.get(
                chave
            )

            if dados_fase is None:

                log(
                    f"Fase não encontrada nos dados do Flutter: "
                    f"{nome_edesk}"
                )

                fases_nao_encontradas.append(
                    nome_edesk
                )

                continue

            data_inicial_desejada = (
                dados_fase["dataInicial"]
            )

            data_final_desejada = (
                dados_fase["dataFinal"]
            )

            # ========================================================
            # CAMPO INICIAL
            # ========================================================

            valor_inicial_antes = ""

            if i < qtd_inicio:

                campo_inicio = datas_inicio.nth(
                    i
                )

                try:

                    valor_inicial_antes = (
                        await campo_inicio.input_value()
                    ).strip()

                except Exception:
                    valor_inicial_antes = ""

                log(
                    "Dt. Ini. Ajustada antes: "
                    f"{valor_inicial_antes or '(vazio)'}"
                )

                if data_inicial_desejada:

                    try:

                        await campo_inicio.fill(
                            data_inicial_desejada
                        )

                        valor_inicial_depois = (
                            await campo_inicio.input_value()
                        ).strip()

                        log(
                            "Dt. Ini. Ajustada depois: "
                            f"{valor_inicial_depois or '(vazio)'}"
                        )

                        if valor_inicial_depois != data_inicial_desejada:

                            log(
                                "ERRO: valor da Dt. Ini. Ajustada "
                                "não ficou conforme solicitado."
                            )

                            erros.append({
                                "fase": nome_edesk,
                                "campo": "Dt. Ini. Ajustada",
                                "esperado": data_inicial_desejada,
                                "encontrado": valor_inicial_depois,
                            })

                    except Exception as e:

                        log(
                            f"ERRO preenchendo Dt. Ini. Ajustada: {e}"
                        )

                        erros.append({
                            "fase": nome_edesk,
                            "campo": "Dt. Ini. Ajustada",
                            "erro": str(e),
                        })

                else:

                    log(
                        "Flutter não enviou Data Inicial "
                        "para esta fase. Campo não alterado."
                    )

            # ========================================================
            # CAMPO FINAL
            # ========================================================

            valor_final_antes = ""

            if i < qtd_fim:

                campo_fim = datas_fim.nth(
                    i
                )

                try:

                    valor_final_antes = (
                        await campo_fim.input_value()
                    ).strip()

                except Exception:
                    valor_final_antes = ""

                log(
                    "Dt. Fin. Ajustada antes: "
                    f"{valor_final_antes or '(vazio)'}"
                )

                if data_final_desejada:

                    try:

                        await campo_fim.fill(
                            data_final_desejada
                        )

                        valor_final_depois = (
                            await campo_fim.input_value()
                        ).strip()

                        log(
                            "Dt. Fin. Ajustada depois: "
                            f"{valor_final_depois or '(vazio)'}"
                        )

                        if valor_final_depois != data_final_desejada:

                            log(
                                "ERRO: valor da Dt. Fin. Ajustada "
                                "não ficou conforme solicitado."
                            )

                            erros.append({
                                "fase": nome_edesk,
                                "campo": "Dt. Fin. Ajustada",
                                "esperado": data_final_desejada,
                                "encontrado": valor_final_depois,
                            })

                    except Exception as e:

                        log(
                            f"ERRO preenchendo Dt. Fin. Ajustada: {e}"
                        )

                        erros.append({
                            "fase": nome_edesk,
                            "campo": "Dt. Fin. Ajustada",
                            "erro": str(e),
                        })

                else:

                    log(
                        "Flutter não enviou Data Final "
                        "para esta fase. Campo não alterado."
                    )

            # ========================================================
            # REGISTRAR RESULTADO
            # ========================================================

            fases_atualizadas.append({
                "nome": nome_edesk,
                "dataInicial": data_inicial_desejada,
                "dataFinal": data_final_desejada,
                "indice": i + 1,
                "somentePreenchida": True,
                "salva": False,
            })

            log(
                f"FASE #{i + 1} PROCESSADA:"
            )

            log(
                f"  Nome: {nome_edesk}"
            )

            log(
                f"  Dt. Ini. Ajustada: "
                f"{data_inicial_desejada or '(não informada)'}"
            )

            log(
                f"  Dt. Fin. Ajustada: "
                f"{data_final_desejada or '(não informada)'}"
            )

            log(
                "  Status: PREENCHIDA NA TELA"
            )

        # ============================================================
        # CONFERÊNCIA FINAL
        # ============================================================

        log("")
        log("=" * 70)
        log("CONFERÊNCIA FINAL DAS DATAS PREENCHIDAS")
        log("=" * 70)

        for i in range(
            quantidade
        ):

            nome = ""

            if i < qtd_nomes:

                try:

                    nome = (
                        await nomes.nth(i).inner_text()
                    ).strip()

                except Exception:
                    nome = ""

            inicio_final = ""

            if i < qtd_inicio:

                try:

                    inicio_final = (
                        await datas_inicio.nth(i).input_value()
                    ).strip()

                except Exception:
                    inicio_final = ""

            fim_final = ""

            if i < qtd_fim:

                try:

                    fim_final = (
                        await datas_fim.nth(i).input_value()
                    ).strip()

                except Exception:
                    fim_final = ""

            log(
                f"FASE #{i + 1} | "
                f"{nome or '(sem nome)'} | "
                f"Dt. Ini. Ajustada={inicio_final or '(vazio)'} | "
                f"Dt. Fin. Ajustada={fim_final or '(vazio)'}"
            )

        # ============================================================
        # RESULTADO
        # ============================================================

        log("")
        log("=" * 70)
        log("PREENCHIMENTO CONCLUÍDO")
        log("=" * 70)

        log(
            f"Fases preenchidas: "
            f"{len(fases_atualizadas)}"
        )

        log(
            f"Fases não encontradas: "
            f"{len(fases_nao_encontradas)}"
        )

        log(
            f"Erros: "
            f"{len(erros)}"
        )

        log(
            "NENHUM BOTÃO SALVAR FOI ACIONADO."
        )

        log(
            "As datas permanecem somente na tela do E-Desk."
        )

        return {
            "atualizadas": fases_atualizadas,
            "naoEncontradas": fases_nao_encontradas,
            "erros": erros,
        }

    except Exception as e:

        log(
            f"ERRO AO PREENCHER FASES: {e}"
        )

        raise


# ================================================================
# SALVAR FASES
#
# SEGURANÇA:
#
# - O salvamento permanece disponível no código.
# - Porém está BLOQUEADO enquanto:
#
#       PERMITIR_SALVAMENTO = False
#
# ================================================================

async def salvar_fases(page, fases_esperadas=None):

    log("")
    log("=" * 70)
    log("SOLICITAÇÃO DE SALVAMENTO DE FASES")
    log("=" * 70)

    # ============================================================
    # TRAVA DE SEGURANÇA
    # ============================================================

    if not PERMITIR_SALVAMENTO:

        log("")
        log("=" * 70)
        log("SALVAMENTO BLOQUEADO POR SEGURANÇA")
        log("=" * 70)

        log(
            "PERMITIR_SALVAMENTO = True"
        )

        log(
            "Nenhum botão Salvar será localizado ou acionado."
        )

        return {
            "salvo": False,
            "bloqueado": True,
            "mensagemSucesso": False,
            "erro": (
                "Salvamento bloqueado pela configuração "
                "de segurança."
            ),
        }

    # ============================================================
    # A PARTIR DAQUI, SALVAMENTO SOMENTE SE LIBERADO
    # ============================================================

    log("")
    log("=" * 70)
    log("SALVANDO FASES NO E-DESK")
    log("=" * 70)

    try:

        view = page.locator(
            "#cph1_rpvFasePro"
        )

        if await view.count() == 0:

            raise Exception(
                "A view cph1_rpvFasePro não existe."
            )

        if not await view.is_visible():

            raise Exception(
                "A view cph1_rpvFasePro não está visível."
            )

        candidatos = []

        elementos = page.get_by_role('button', name=re.compile(r'^salvar$', re.I)).or_(
            page.get_by_role('link', name=re.compile(r'^salvar$', re.I)))

        quantidade = await elementos.count()

        log(
            f"Elementos candidatos dentro da view: {quantidade}"
        )

        for i in range(
            quantidade
        ):

            try:

                elemento = elementos.nth(i)

                if not await elemento.is_visible():
                    continue

                tag = await elemento.evaluate(
                    "(e) => e.tagName"
                )

                id_elemento = (
                    await elemento.get_attribute("id")
                    or ""
                )

                name_elemento = (
                    await elemento.get_attribute("name")
                    or ""
                )

                value_elemento = (
                    await elemento.get_attribute("value")
                    or ""
                )

                title_elemento = (
                    await elemento.get_attribute("title")
                    or ""
                )

                aria_label = (
                    await elemento.get_attribute("aria-label")
                    or ""
                )

                texto_elemento = ""

                try:

                    texto_elemento = (
                        await elemento.inner_text(
                            timeout=300
                        )
                    ).strip()

                except Exception:
                    pass

                texto_busca = " ".join([
                    texto_elemento,
                    value_elemento,
                    title_elemento,
                    aria_label,
                ])

                texto_normalizado = normalizar(
                    texto_busca
                )

                log(
                    f"CANDIDATO {i} | "
                    f"tag={tag} | "
                    f"id={id_elemento} | "
                    f"name={name_elemento} | "
                    f"value={value_elemento} | "
                    f"title={title_elemento} | "
                    f"texto={texto_elemento}"
                )

                eh_salvar = (
                    texto_normalizado == "salvar"
                    or normalizar(value_elemento) == "salvar"
                    or normalizar(title_elemento) == "salvar"
                    or normalizar(aria_label) == "salvar"
                )

                if eh_salvar:

                    candidatos.append(
                        elemento
                    )

            except Exception:
                continue

        log(
            f"Botões 'Salvar' encontrados: "
            f"{len(candidatos)}"
        )

        if len(candidatos) == 0:

            raise Exception(
                "Nenhum botão 'Salvar' visível foi encontrado "
                "dentro da área de Fases."
            )

        if len(candidatos) > 1:

            log(
                "Mais de um botão 'Salvar' foi encontrado."
            )

            candidatos_prioritarios = []

            for elemento in candidatos:

                try:

                    tag = await elemento.evaluate(
                        "(e) => e.tagName"
                    )

                    if tag in (
                        "INPUT",
                        "BUTTON",
                    ):

                        candidatos_prioritarios.append(
                            elemento
                        )

                except Exception:
                    pass

            if len(candidatos_prioritarios) == 1:

                candidatos = candidatos_prioritarios

            elif len(candidatos_prioritarios) > 1:

                raise Exception(
                    "Foram encontrados vários botões "
                    "'Salvar' e não foi possível identificar "
                    "com segurança qual pertence às Fases."
                )

            else:

                raise Exception(
                    "Foram encontrados vários elementos "
                    "'Salvar' e não foi possível identificar "
                    "com segurança qual pertence às Fases."
                )

        botao_salvar = candidatos[0]

        try:

            log(
                "Botão Salvar selecionado:"
            )

            log(
                f"  tag={await botao_salvar.evaluate('(e) => e.tagName')}"
            )

            log(
                f"  id={await botao_salvar.get_attribute('id')}"
            )

            log(
                f"  name={await botao_salvar.get_attribute('name')}"
            )

            log(
                f"  value={await botao_salvar.get_attribute('value')}"
            )

            log(
                f"  texto={await botao_salvar.inner_text()}"
            )

        except Exception:
            pass

        await botao_salvar.wait_for(
            state="visible",
            timeout=10000,
        )

        log(
            "Clicando em SALVAR FASES..."
        )

        if not fases_esperadas:
            raise ValueError('Nenhuma fase disponível para confirmar o salvamento.')
        async with page.expect_response(lambda response:
                response.request.method == 'POST' and
                '/Portal/Solicitacao.aspx' in response.url, timeout=20000) as saved_response:
            await botao_salvar.click(timeout=15000)
        response = await saved_response.value
        await response.body()
        if response.status >= 400:
            raise ValueError('O E-Desk recusou o salvamento das fases.')

        log(
            "Clique em SALVAR executado."
        )

        log(
            "Aguardando processamento do E-Desk..."
        )

        await page.reload(wait_until='domcontentloaded', timeout=30000)
        if not await abrir_fases(page):
            raise ValueError('Não foi possível reabrir as fases para confirmar o salvamento.')
        differences = mismatched_phases(fases_esperadas, await read_phase_rows(page))
        if differences:
            raise ValueError(' '.join(differences))

        return {
            "salvo": True,
            "mensagemSucesso": False,
        }

    except Exception as e:

        log(
            f"ERRO AO SALVAR FASES: {e}"
        )

        return {
            "salvo": False,
            "mensagemSucesso": False,
            "erro": str(e),
        }


# ================================================================
# EXECUÇÃO PRINCIPAL
# ================================================================

async def executar():
    global PERMITIR_SALVAMENTO
    request = ler_request()
    PERMITIR_SALVAMENTO = bool(request and request.get('enviar') is True)

    if not request:

        raise Exception(
            "Nenhum JSON recebido."
        )

    # ============================================================
    # DADOS
    # ============================================================

    url = (
        request.get("url")
        or BASE_URL
    )

    solicitacao = (
        request.get("solicitacao")
        or request.get("id")
        or request.get("numero")
        or ""
    )

    cliente = (
        request.get("cliente")
        or ""
    )

    fases = (
        request.get("fases")
        or []
    )

    # ============================================================
    # CREDENCIAIS
    # ============================================================

    edesk_email, edesk_senha = obter_credenciais_edesk(
        request
    )

    log("")
    log("=" * 70)
    log("INÍCIO DA EXECUÇÃO E-DESK - FASES")
    log("=" * 70)

    log(
        f"URL inicial: {url}"
    )

    log(
        f"Solicitação: {solicitacao}"
    )

    log(
        f"Cliente: {cliente}"
    )

    log(
        f"Fases recebidas: {len(fases)}"
    )

    log(
        "Credenciais E-Desk recebidas: "
        f"{'SIM' if edesk_email and edesk_senha else 'NÃO'}"
    )

    log(
        f"PERMITIR_SALVAMENTO: {PERMITIR_SALVAMENTO}"
    )

    # ============================================================
    # PLAYWRIGHT
    # ============================================================

    async with async_playwright() as p:

        context = None

        try:

            PROFILE_DIR.mkdir(
                parents=True,
                exist_ok=True
            )

            context = await p.chromium.launch_persistent_context(

                user_data_dir=str(
                    PROFILE_DIR
                ),

                headless=HEADLESS,

                viewport={
                    "width": 1440,
                    "height": 900,
                },

                args=[
                    "--start-maximized",
                ],
            )

            log(
                "Navegador iniciado."
            )

            # ====================================================
            # PÁGINA PRINCIPAL
            # ====================================================

            paginas = list(
                context.pages
            )

            if paginas:

                page = paginas[0]

            else:

                page = await context.new_page()

            log(
                f"Página inicial: {page.url}"
            )

            if (
                not page.url
                or page.url == "about:blank"
            ):

                await page.goto(
                    url,
                    wait_until="domcontentloaded"
                )

            else:

                if (
                    "promob.e-desk.com.br"
                    not in page.url
                    and "promobid.promob.com"
                    not in page.url
                    and "identity.promob.com"
                    not in page.url
                ):

                    await page.goto(
                        url,
                        wait_until="domcontentloaded"
                    )

            await asyncio.sleep(
                1.5
            )

            # ====================================================
            # LOGIN
            # ====================================================

            await esperar_login(
                page,
                email=edesk_email,
                senha=edesk_senha
            )

            # ====================================================
            # MINHA GRID
            # ====================================================

            page = await abrir_minha_grid(
                page
            )

            # ====================================================
            # SOLICITAÇÃO
            #
            # IMPORTANTE:
            #
            # Esta é a ÚNICA abertura da Solicitação.
            # ====================================================

            page = await pesquisar_solicitacao(
                page,
                solicitacao
            )

            # ====================================================
            # FASES
            # ====================================================

            fases_abertas = await abrir_fases(
                page
            )

            if not fases_abertas:

                raise Exception(
                    "Não foi possível abrir a aba Fases."
                )

            # ====================================================
            # PREENCHIMENTO
            # ====================================================

            resultado_fases = await atualizar_fases(
                page,
                fases
            )

            fases_atualizadas = (
                resultado_fases.get(
                    "atualizadas",
                    []
                )
                if isinstance(
                    resultado_fases,
                    dict
                )
                else []
            )

            fases_nao_encontradas = (
                resultado_fases.get(
                    "naoEncontradas",
                    []
                )
                if isinstance(
                    resultado_fases,
                    dict
                )
                else []
            )

            erros = (
                resultado_fases.get(
                    "erros",
                    []
                )
                if isinstance(
                    resultado_fases,
                    dict
                )
                else []
            )

            # ====================================================
            # SALVAMENTO
            #
            # Salva somente depois que o preenchimento terminou
            # sem erros e pelo menos uma fase foi atualizada.
            # ====================================================

            resultado_salvamento = {
                "salvo": False,
                "mensagemSucesso": False,
            }

            if fases_atualizadas and not erros:

                resultado_salvamento = await salvar_fases(
                    page, fases_atualizadas
                )

                if not resultado_salvamento.get(
                    "salvo",
                    False
                ):

                    erro_salvamento = (
                        resultado_salvamento.get(
                            "erro"
                        )
                        or "Não foi possível salvar as fases no E-Desk."
                    )

                    erros.append(
                        erro_salvamento
                    )

            salvo = bool(
                resultado_salvamento.get(
                    "salvo",
                    False
                )
            )
            if salvo:
                for index in range(len(fases_atualizadas)):
                    fases_atualizadas[index]['salva'] = True
                    fases_atualizadas[index]['somentePreenchida'] = False
                    completed(f'phase-{index}')

            # ====================================================
            # RESULTADO
            # ====================================================

            log("")
            log("=" * 70)
            log("RESULTADO FINAL")
            log("=" * 70)

            log(
                f"Fases preenchidas: "
                f"{len(fases_atualizadas)}"
            )

            log(
                f"Fases não encontradas: "
                f"{len(fases_nao_encontradas)}"
            )

            log(
                f"Erros: "
                f"{len(erros)}"
            )

            if salvo:

                log(
                    "Fases salvas no E-Desk."
                )

            else:

                log(
                    "As fases não foram salvas."
                )

            responder({

                "ok": (
                    len(erros) == 0
                    and salvo
                ),

                "message": (
                    "Fases atualizadas e salvas no E-Desk."
                    if salvo
                    else "As fases foram preenchidas, mas não foi possível salvar."
                ),

                "atualizadas": fases_atualizadas,

                "naoEncontradas": fases_nao_encontradas,

                "erros": erros,

                "urlSolicitacao": page.url,

            })

        except Exception as e:

            log(
                f"ERRO: {e}"
            )

            responder({

                "ok": False,

                "message": (
                    f"Erro durante o preenchimento: {e}"
                ),

                "atualizadas": [],

                "naoEncontradas": [],

                "erros": [
                    str(e)
                ],
            })

        finally:

            if context is not None:

                try:

                    log("")
                    log("=" * 70)
                    log("ENCERRANDO A EXECUÇÃO DE FASES")
                    log("=" * 70)

                    log(
                        "Devolvendo o resultado ao aplicativo."
                    )

                    log(
                        "O perfil e a sessão permanecem salvos."
                    )

                    log(
                        f"Salvamento habilitado: "
                        f"PERMITIR_SALVAMENTO={PERMITIR_SALVAMENTO}"
                    )

                    await context.close()

                except Exception as e:

                    log(
                        f"Erro mantendo navegador aberto: {e}"
                    )


# ================================================================
# MAIN
# ================================================================

if __name__ == "__main__":

    try:

        asyncio.run(
            executar()
        )

    except KeyboardInterrupt:

        log(
            "Execução interrompida pelo usuário."
        )

    except Exception as e:

        log(
            f"Erro fatal: {e}"
        )

        responder({

            "ok": False,

            "message": str(e),

            "atualizadas": [],

            "naoEncontradas": [],

            "erros": [
                str(e)
            ],
        })
