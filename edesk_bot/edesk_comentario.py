from config import restore_session_cookies, save_session_cookies
import sys
import re
from comment_percentage import (parse_percentage,
                                save_work_percentage, save_comment_then_percentage, update_percentage_after_comment)
from edesk_horas import localizar_solicitacao as localizar_solicitacao_validada
from edesk_horas import abrir_trabalho as abrir_trabalho_validado
from edesk_horas import abrir_trabalho_na_solicitacao

from send_progress import observe_log
import json
import time
import html
from pathlib import Path
from urllib.parse import urlparse, parse_qs

from playwright.sync_api import (
    sync_playwright,
    Error as PlaywrightError,
    TimeoutError as PlaywrightTimeoutError,
)

from config import (
    HEADLESS,
    PROFILE_DIR,
    SCREENSHOTS_DIR,
    LOGS_DIR,
    COMENTARIO_TIPOS,
)


# ================================================================
# CAMINHOS
# ================================================================

BASE_DIR = Path(__file__).resolve().parent

PROFILE_PATH = BASE_DIR / PROFILE_DIR
SCREENSHOTS_PATH = BASE_DIR / SCREENSHOTS_DIR
LOGS_PATH = BASE_DIR / LOGS_DIR

PROFILE_PATH.mkdir(parents=True, exist_ok=True)
SCREENSHOTS_PATH.mkdir(parents=True, exist_ok=True)
LOGS_PATH.mkdir(parents=True, exist_ok=True)


# ================================================================
# LOG
# ================================================================

def log(mensagem):
    observe_log(mensagem)

    print(
        f"[E-Desk][Python] {mensagem}",
        flush=True,
    )


# ================================================================
# REQUEST
# ================================================================

def carregar_request():

    if len(sys.argv) < 2:

        raise RuntimeError(
            "Nenhum arquivo request.json foi informado."
        )

    request_path = Path(
        sys.argv[1]
    )

    log(
        f"Request recebido: {request_path}"
    )

    if not request_path.exists():

        raise RuntimeError(
            f"Request não encontrado: {request_path}"
        )

    with request_path.open(
        "r",
        encoding="utf-8",
    ) as arquivo:

        return json.load(arquivo)


# ================================================================
# DADOS
# ================================================================

def obter_url(dados):

    url = str(
        dados.get(
            "url",
            "",
        )
    ).strip()

    if not url:

        raise RuntimeError(
            "A URL do E-Desk não foi informada."
        )

    return url


def obter_tipo_comentario(dados):

    tipo = str(
        dados.get(
            "tipo",
            "Interno",
        )
    ).strip()

    if tipo in COMENTARIO_TIPOS:

        return COMENTARIO_TIPOS[tipo]

    if tipo in {
        "0",
        "1",
        "3",
        "4",
    }:

        return tipo

    raise RuntimeError(
        f"Tipo de comentário inválido: {tipo}"
    )


def obter_texto(dados):

    return str(
        dados.get(
            "texto",
            "",
        )
    )


def obter_imagem_base64(dados):

    imagem = dados.get(
        "imagemBase64"
    )

    if not imagem:

        return None

    imagem = str(
        imagem
    ).strip()

    if not imagem:

        return None

    return imagem


def extrair_id_trabalho(dados):

    return str(
        dados.get(
            "idTrabalho",
            "",
        )
    ).strip()


def extrair_solicitacao(dados):

    return str(
        dados.get(
            "solicitacao",
            "",
        )
    ).strip()


# ================================================================
# GUID
# ================================================================

def obter_guid_da_url(url):

    try:

        parametros = parse_qs(
            urlparse(url).query
        )

        return parametros.get(
            "GUID",
            [""],
        )[0]

    except Exception:

        return ""


# ================================================================
# LOGIN
# ================================================================

SELETORES_EMAIL_LOGIN = [
    "input[type='email']",
    "input[autocomplete='username']",
    "input[name*='email' i]",
    "input[id*='email' i]",
]
SELETORES_SENHA_LOGIN = [
    "input[type='password']",
    "input[autocomplete='current-password']",
    "input[name*='senha' i]",
    "input[id*='senha' i]",
    "input[name*='password' i]",
    "input[id*='password' i]",
]
SELETORES_ENTRAR_LOGIN = [
    "button:has-text('Entrar')",
    "input[type='submit']",
    "button[type='submit']",
]


def obter_credenciais_edesk(dados):
    credenciais = dados.get("edeskCredenciais")
    if not isinstance(credenciais, dict):
        return None

    email = str(credenciais.get("email", "") or "").strip()
    senha = str(credenciais.get("senha", "") or "")
    if not email or not senha:
        return None

    return {"email": email, "senha": senha}


def _localizar_campo_login(page, seletores):
    for frame in page.frames:
        for seletor in seletores:
            try:
                elementos = frame.locator(seletor)
                for indice in range(elementos.count()):
                    elemento = elementos.nth(indice)
                    if elemento.is_visible():
                        return elemento
            except Exception:
                continue
    return None


def _tentar_login_automatico(page, credenciais):
    campo_email = _localizar_campo_login(page, SELETORES_EMAIL_LOGIN)
    campo_senha = _localizar_campo_login(page, SELETORES_SENHA_LOGIN)
    if campo_email is None or campo_senha is None:
        return False

    campo_email.fill(credenciais["email"])
    campo_senha.fill(credenciais["senha"])

    botao_entrar = _localizar_campo_login(page, SELETORES_ENTRAR_LOGIN)
    if botao_entrar is not None:
        botao_entrar.click()
    else:
        campo_senha.press("Enter")

    log("Credenciais E-Desk enviadas para autenticação.")
    return True


def aguardar_login(
    page,
    timeout_segundos=300,
    credenciais=None,
):

    log("")
    log("========================================")
    log("AGUARDANDO AUTENTICAÇÃO DO PROMOB")
    log("========================================")
    log("")

    log(
        "Faça o login normalmente no navegador."
    )

    log("")

    inicio = time.time()
    ultimo_url = ""
    tentativa_automatica_realizada = False

    while True:

        if (
            time.time() - inicio
            > timeout_segundos
        ):

            raise RuntimeError(
                "Tempo limite de autenticação excedido."
            )

        try:

            url_atual = page.url

        except Exception:

            url_atual = ""

        if url_atual != ultimo_url:

            log(
                f"URL atual: {url_atual}"
            )

            ultimo_url = url_atual

        # --------------------------------------------------------
        # PORTAL AUTENTICADO
        # --------------------------------------------------------

        if (
            "/Portal/PortalAtendente.aspx"
            in url_atual
        ):

            log("")
            log("========================================")
            log("AUTENTICAÇÃO CONCLUÍDA")
            log(
                "Portal do Atendente detectado."
            )
            log("========================================")
            log("")

            return

        # --------------------------------------------------------
        # JÁ ESTÁ EM UM TRABALHO
        # --------------------------------------------------------

        try:

            botao = page.locator(
                "#cph1_BtCom"
            )

            if botao.count() > 0:

                try:

                    if botao.first.is_visible(
                        timeout=1000
                    ):

                        log("")
                        log(
                            "========================================"
                        )
                        log(
                            "AUTENTICAÇÃO CONCLUÍDA"
                        )
                        log(
                            "Tela de trabalho detectada."
                        )
                        log(
                            "========================================"
                        )
                        log("")

                        return

                except Exception:

                    pass

        except Exception:

            pass

        if credenciais and not tentativa_automatica_realizada:
            try:
                tentativa_automatica_realizada = _tentar_login_automatico(
                    page,
                    credenciais,
                )
                if tentativa_automatica_realizada:
                    log("Aguardando confirmação do login automático.")
            except Exception as erro:
                log(f"Não foi possível preencher o login E-Desk: {erro}")
                tentativa_automatica_realizada = True

        time.sleep(1)


# ================================================================
# ACESSAR MINHA GRID
# ================================================================

def acessar_minha_grid(
    page,
    guid=None,
):

    log("")
    log("============================================")
    log("ACESSANDO MINHA GRID")
    log("============================================")

    guid = str(
        guid
        or obter_guid_da_url(page.url)
        or ""
    ).strip()

    if not guid:
        raise RuntimeError(
            "GUID da sessão do E-Desk não encontrado."
        )

    url_grid = (
        "https://promob.e-desk.com.br/"
        "Portal/ListaSolicitacao.aspx?"
        f"GUID={guid}"
    )

    log(
        f"Acessando Grid: {url_grid}"
    )

    try:
        page.goto(
            url_grid,
            wait_until="domcontentloaded",
            timeout=60000,
        )
    except Exception as erro:
        log(
            f"Aviso durante acesso à Grid: {erro}"
        )

    try:
        page.locator("#cph1_txtSol").first.wait_for(state="visible", timeout=20000)
    except Exception as error:
        raise RuntimeError("EDESK_GRID_SEARCH_NOT_READY") from error

    log(
        f"URL atual da Grid: {page.url}"
    )


# ================================================================
# MONITOR DE REQUESTS
#
# Deve ser instalado ANTES de acessar a Grid.
# ================================================================

def instalar_monitor_requests(page):

    def monitor_request(request):

        try:
            url = request.url

            paginas_interesse = [
                "ListaSolicitacao.aspx",
                "Solicitacao.aspx",
                "Trabalho.aspx",
                "TrabalhoRetroativo.aspx",
            ]

            if not any(
                pagina in url
                for pagina in paginas_interesse
            ):
                return

            log("")
            log(">>> REQUEST")
            log(f"MÉTODO: {request.method}")
            log(f"URL: {url}")

            try:
                post_data = request.post_data

                if post_data:
                    log("POST DATA:")
                    log(post_data)
            except Exception:
                pass

        except Exception:
            pass

    page.on(
        "request",
        monitor_request,
    )


# ================================================================
# CRIAR NOVA ABA DA GRID
#
# Usa o MESMO CONTEXTO, MESMA SESSÃO e MESMO GUID.
# Não executa novo login.
# ================================================================

def criar_nova_pagina_grid(
    context,
    guid_sessao,
):

    log("")
    log("============================================================")
    log("CRIANDO NOVA ABA DA GRID")
    log("============================================================")

    pagina_grid = context.new_page()

    try:
        pagina_grid.bring_to_front()
    except Exception:
        pass

    instalar_monitor_requests(
        pagina_grid
    )

    acessar_minha_grid(
        pagina_grid,
        guid_sessao,
    )

    try:
        pagina_grid.wait_for_selector(
            "#ctl00_cph1_hgrSol_ctl00",
            state="attached",
            timeout=30000,
        )
    except Exception as erro:
        raise RuntimeError(
            "A tabela de solicitações não foi encontrada "
            f"na nova Grid: {erro}"
        )

    log("NOVA GRID CRIADA COM SUCESSO.")
    log(f"URL: {pagina_grid.url}")

    return pagina_grid


def eh_grid_url(url):

    return "ListaSolicitacao.aspx" in (url or "")


def fechar_pagina_sessao_antiga(
    pagina_antiga,
    pagina_grid,
):

    if pagina_antiga is None:
        return

    try:
        if pagina_antiga.is_closed():
            return
    except Exception:
        return

    if pagina_antiga == pagina_grid:
        return

    log("")
    log("============================================")
    log("FECHANDO PÁGINA ANTIGA DA SESSÃO")
    log("============================================")
    log(f"URL antiga: {pagina_antiga.url}")

    try:
        pagina_antiga.close()
    except Exception as erro:
        log(
            f"Aviso ao fechar página antiga: {erro}"
        )

    try:
        pagina_grid.bring_to_front()
    except Exception:
        pass


# ================================================================
# LOCALIZAR SOLICITAÇÃO NA GRID
# ================================================================

def localizar_solicitacao(
    page,
    numero_solicitacao,
):

    numero_solicitacao = str(
        numero_solicitacao
    ).strip()

    log("")
    log("============================================")
    log("LOCALIZANDO SOLICITAÇÃO NA GRID")
    log("============================================")
    log(
        f"Solicitação procurada: {numero_solicitacao}"
    )

    seletor_tabela = (
        "#ctl00_cph1_hgrSol_ctl00"
    )

    # ============================================================
    # 1. GARANTIR QUE O RADGRID EXISTE
    # ============================================================

    tabela = page.locator(
        seletor_tabela
    )

    try:

        tabela.wait_for(
            state="visible",
            timeout=30000,
        )

    except Exception as erro:

        raise RuntimeError(
            "A tabela principal da Minha Grid não ficou visível: "
            f"{erro}"
        )

    # ============================================================
    # 2. PRIMEIRA TENTATIVA:
    #    LINHAS DOM DO RADGRID
    # ============================================================

    linhas = page.locator(
        seletor_tabela
        + " tr.rgRow, "
        + seletor_tabela
        + " tr.rgAltRow"
    )

    try:

        quantidade = linhas.count()

    except Exception:

        quantidade = 0

    log(
        "Linhas rgRow/rgAltRow no DOM: "
        f"{quantidade}"
    )

    for i in range(
        quantidade
    ):

        linha = linhas.nth(i)

        try:

            texto = linha.inner_text(
                timeout=1000
            ).strip()

            if (
                texto == numero_solicitacao
                or numero_solicitacao in texto
            ):

                log(
                    f"Solicitação {numero_solicitacao} "
                    f"encontrada no DOM na linha {i}."
                )

                return [linha]

            celulas = linha.locator(
                "td"
            )

            if celulas.count() >= 2:

                numero = celulas.nth(
                    1
                ).inner_text(
                    timeout=1000
                ).strip()

                if numero == numero_solicitacao:

                    log(
                        f"Solicitação {numero_solicitacao} "
                        f"encontrada na coluna padrão da linha {i}."
                    )

                    return [linha]

        except Exception:

            continue

    # ============================================================
    # 3. AGUARDAR OS REGISTROS REAIS DO TELERIK
    #
    # O RadGrid pode existir no DOM antes de o Telerik terminar
    # de preencher os dataItems. Não usamos somente um sleep fixo.
    # Esperamos o próprio objeto do Telerik possuir registros.
    # ============================================================

    try:

        page.wait_for_function(
            """
            () => {

                if (!window.$find) {
                    return false;
                }

                const grid = window.$find(
                    \"ctl00_cph1_hgrSol\"
                );

                if (!grid || !grid.get_masterTableView) {
                    return false;
                }

                const view = grid.get_masterTableView();

                if (!view || !view.get_dataItems) {
                    return false;
                }

                return view.get_dataItems().length > 0;
            }
            """,
            timeout=30000,
        )

        log(
            "Telerik RadGrid terminou de carregar os registros."
        )

    except Exception as erro:

        log(
            "Aviso aguardando dataItems do Telerik: "
            f"{erro}"
        )

    # ============================================================
    # 4. SEGUNDA TENTATIVA:
    #    RADGRID CLIENT-SIDE DO TELERIK
    #
    # O log atual mostra exatamente o caso em que:
    #   tabela existe
    #   tr existe
    #   rgRow/rgAltRow = 0
    #
    # Nesse cenário os registros podem estar somente no objeto
    # JavaScript do RadGrid.
    # ============================================================

    log("")
    log(
        "Consultando os dataItems internos do Telerik RadGrid..."
    )

    try:

        resultado = page.evaluate(
            """
            (solicitacao) => {

                const retorno = {
                    gridEncontrado: false,
                    masterTableView: false,
                    quantidade: 0,
                    correspondencia: null,
                    amostras: []
                };

                try {

                    if (!window.$find) {
                        return retorno;
                    }

                    const grid = window.$find(
                        "ctl00_cph1_hgrSol"
                    );

                    if (!grid) {
                        return retorno;
                    }

                    retorno.gridEncontrado = true;

                    const view = grid.get_masterTableView
                        ? grid.get_masterTableView()
                        : null;

                    if (!view) {
                        return retorno;
                    }

                    retorno.masterTableView = true;

                    const itens = view.get_dataItems
                        ? view.get_dataItems()
                        : [];

                    retorno.quantidade = itens.length;

                    const nomes = [
                        "ID",
                        "Id",
                        "id",
                        "Solicitacao",
                        "solicitacao",
                        "Numero",
                        "numero",
                        "IdSolicitacao",
                        "IDSolicitacao",
                        "CodSolicitacao",
                        "CodigoSolicitacao"
                    ];

                    const alvo = String(
                        solicitacao || ""
                    ).trim();

                    for (let i = 0; i < itens.length; i++) {

                        const item = itens[i];

                        let elemento = null;
                        let texto = "";
                        let rowId = "";
                        let itemIndex = null;
                        const valores = {};

                        try {
                            elemento = item.get_element();
                        } catch (_) {}

                        try {
                            if (elemento) {
                                texto = String(
                                    elemento.innerText || ""
                                ).trim();
                                rowId = String(
                                    elemento.id || ""
                                );
                            }
                        } catch (_) {}

                        try {
                            if (item.get_itemIndex) {
                                itemIndex = item.get_itemIndex();
                            }
                        } catch (_) {}

                        for (const nome of nomes) {

                            try {

                                if (!item.getDataKeyValue) {
                                    continue;
                                }

                                const valor =
                                    item.getDataKeyValue(nome);

                                if (
                                    valor !== undefined &&
                                    valor !== null &&
                                    String(valor).trim() !== ""
                                ) {
                                    valores[nome] = String(valor);
                                }

                            } catch (_) {}
                        }

                        if (retorno.amostras.length < 10) {
                            retorno.amostras.push({
                                indice: i,
                                itemIndex: itemIndex,
                                rowId: rowId,
                                texto: texto,
                                valores: valores
                            });
                        }

                        let encontrou = false;

                        if (
                            alvo &&
                            texto &&
                            (
                                texto === alvo ||
                                texto.includes(alvo)
                            )
                        ) {
                            encontrou = true;
                        }

                        if (!encontrou && alvo) {

                            for (const chave of Object.keys(valores)) {

                                if (
                                    String(valores[chave]).trim() === alvo
                                ) {
                                    encontrou = true;
                                    break;
                                }
                            }
                        }

                        if (encontrou) {

                            retorno.correspondencia = {
                                indice: i,
                                itemIndex: itemIndex,
                                rowId: rowId,
                                texto: texto,
                                valores: valores
                            };

                            break;
                        }
                    }

                } catch (erro) {

                    retorno.erro = String(erro);
                }

                return retorno;
            }
            """,
            numero_solicitacao,
        )

        log(
            "RadGrid encontrado: "
            f"{resultado.get('gridEncontrado')}"
        )

        log(
            "MasterTableView encontrado: "
            f"{resultado.get('masterTableView')}"
        )

        log(
            "Quantidade de dataItems: "
            f"{resultado.get('quantidade', 0)}"
        )

        correspondencia = resultado.get(
            "correspondencia"
        )

        if correspondencia:

            row_id = str(
                correspondencia.get(
                    "rowId",
                    "",
                )
                or ""
            ).strip()

            texto = str(
                correspondencia.get(
                    "texto",
                    "",
                )
                or ""
            ).strip()

            item_index = correspondencia.get(
                "itemIndex"
            )

            log("")
            log(
                "SOLICITAÇÃO ENCONTRADA PELO TELERIK"
            )
            log(
                f"Índice do item: {item_index}"
            )
            log(
                f"ID da linha: {row_id}"
            )
            log(
                f"Texto da linha: {texto}"
            )

            if row_id:

                linha = page.locator(
                    f'tr[id="{row_id}"]'
                ).first

                try:

                    linha.wait_for(
                        state="attached",
                        timeout=5000,
                    )

                    return [linha]

                except Exception:

                    pass

                elemento = page.locator(
                    f'[id="{row_id}"]'
                ).first

                try:

                    elemento.wait_for(
                        state="attached",
                        timeout=5000,
                    )

                    return [elemento]

                except Exception:

                    pass

        # ========================================================
        # LOG DE AMOSTRAS SOMENTE QUANDO NÃO ENCONTROU
        # ========================================================

        for amostra in (
            resultado.get("amostras", [])
        ):

            log(
                "ITEM "
                f"{amostra.get('indice')} | "
                f"itemIndex={amostra.get('itemIndex')} | "
                f"rowId={amostra.get('rowId')} | "
                f"texto={str(amostra.get('texto', ''))[:300]}"
            )

            valores = amostra.get(
                "valores",
                {}
            )

            if valores:

                log(
                    f"VALORES: {valores}"
                )

    except Exception as erro:

        log(
            f"Erro consultando os dataItems do Telerik: {erro}"
        )

    # ============================================================
    # 5. ÚLTIMO FALLBACK:
    #    QUALQUER TR COM O NÚMERO
    # ============================================================

    log("")
    log(
        "Tentando localizar a solicitação em qualquer linha da tabela..."
    )

    try:

        todas_linhas = page.locator(
            seletor_tabela
            + " tr"
        )

        quantidade_total = todas_linhas.count()

        log(
            f"Total de linhas no fallback: {quantidade_total}"
        )

        for i in range(
            quantidade_total
        ):

            linha = todas_linhas.nth(i)

            try:

                texto = linha.inner_text(
                    timeout=1000
                ).strip()

                if numero_solicitacao in texto:

                    log(
                        f"Solicitação {numero_solicitacao} "
                        f"encontrada por texto na linha {i}."
                    )

                    return [linha]

            except Exception:

                continue

    except Exception as erro:

        log(
            f"Erro no fallback final: {erro}"
        )

    log(
        f"Solicitação {numero_solicitacao} não encontrada na Grid."
    )

    return []


# ================================================================
# LOCALIZAR PÁGINA DE TRABALHO
# ================================================================

def localizar_pagina_trabalho(context):

    for pagina in list(context.pages):
        try:
            if pagina.is_closed():
                continue

            botao = pagina.locator("#cph1_BtCom")

            if botao.count() > 0 and botao.first.is_visible(
                timeout=500
            ):
                return pagina

        except Exception:
            continue

    return None


# ================================================================
# ABRIR TRABALHO
# ================================================================

def abrir_trabalho(
    page,
    context,
    candidatos,
    id_trabalho,
):

    id_trabalho = str(
        id_trabalho
    ).strip()

    if not candidatos:
        raise RuntimeError(
            "Nenhuma linha candidata foi encontrada."
        )

    log("")
    log("============================================")
    log("LOCALIZANDO TRABALHO")
    log("============================================")
    log(f"ID Trabalho recebido: {id_trabalho}")

    linha = candidatos[0]

    paginas_antes = set(context.pages)

    try:
        linha.scroll_into_view_if_needed()
        linha.dblclick(delay=100)
        log("Duplo clique executado.")
    except Exception as erro:
        raise RuntimeError(
            f"Não foi possível abrir o trabalho: {erro}"
        )

    pagina_trabalho = None
    inicio = time.time()

    while time.time() - inicio < 20:

        pagina_trabalho = localizar_pagina_trabalho(
            context
        )

        if pagina_trabalho is not None:
            break

        # Procurar também apenas páginas novas.
        for pagina in list(context.pages):
            try:
                if pagina.is_closed():
                    continue

                if id(pagina) in {id(p) for p in paginas_antes}:
                    continue

                if "Solicitacao.aspx" in pagina.url:
                    pagina.bring_to_front()
                    page.wait_for_timeout(1000)
                    candidato = localizar_pagina_trabalho(context)
                    if candidato is not None:
                        pagina_trabalho = candidato
                        break
            except Exception:
                continue

        if pagina_trabalho is not None:
            break

        time.sleep(0.5)

    if pagina_trabalho is None:
        raise RuntimeError(
            "O trabalho foi aberto, mas a tela de trabalho "
            "não foi localizada."
        )

    try:
        pagina_trabalho.bring_to_front()
    except Exception:
        pass

    log("")
    log("============================================================")
    log("TRABALHO LOCALIZADO COM SUCESSO")
    log("============================================================")
    log(f"URL: {pagina_trabalho.url}")

    return pagina_trabalho


# ================================================================
# ABRIR COMENTÁRIO
# ================================================================

def abrir_solicitacao_para_comentario(page, context, linha, solicitacao, preaberta=None):
    """Open the request directly; never enter a work or retroactive hours."""
    try:
        return abrir_trabalho_validado(
            page, context, linha, solicitacao, '',
            pagina_solicitacao_preaberta=preaberta,
            abrir_retroativo=False, somente_solicitacao=True)
    except Exception as error:
        raise RuntimeError('EDESK_COMMENT_REQUEST_NOT_OPENED') from error


def selecionar_aba_comentarios(page):
    """Select the request's comments tab before opening a new comment."""
    try:
        aba = page.get_by_text(re.compile(r'^Comentários\s*(?:\(\d+\))?$'))
        aba.wait_for(state='visible', timeout=20000)
        aba.click(timeout=15000)
    except Exception as error:
        raise RuntimeError('EDESK_COMMENT_TAB_NOT_OPENED') from error


def localizar_botao_comentario(page):
    """Match the visible action by its label, regardless of generated ASP.NET ID."""
    nome = re.compile(r'^Coment[aá]rio$', re.IGNORECASE)
    botao = (page.get_by_role('button', name=nome)
             .or_(page.get_by_role('link', name=nome))
             .or_(page.locator('#cph1_BtCom:visible')))
    try:
        botao.wait_for(state='visible', timeout=20000)
        if not botao.is_enabled():
            raise RuntimeError('Comment action disabled')
        return botao
    except Exception as error:
        raise RuntimeError('EDESK_COMMENT_BUTTON_NOT_FOUND') from error


def abrir_comentario(page, context):
    """Abre o popup de comentário e retorna (pagina, frame).

    Mantém o contrato já utilizado pelo main(): o botão de comentários
    é acionado na tela da solicitação e o frame é identificado pelo campo
    de tipo de comentário (#popC_ddlTipCom).
    """

    log("")
    log("============================================")
    log("ABRINDO COMENTÁRIO")
    log("============================================")

    page.bring_to_front()
    selecionar_aba_comentarios(page)

    botao = localizar_botao_comentario(page)

    paginas_antes = set(context.pages)
    botao.click()
    log("Botão Comentários clicado.")

    inicio = time.time()
    ultimo_erro = None

    while time.time() - inicio < 20:
        # O E-Desk pode abrir o comentário na própria página ou em popup.
        paginas = list(context.pages)
        paginas_novas = [p for p in paginas if p not in paginas_antes]
        candidatos = paginas_novas + [p for p in paginas if p not in paginas_novas]

        for pagina in candidatos:
            try:
                if pagina.is_closed():
                    continue

                # Primeiro verifica a própria página; em seguida, seus frames.
                if pagina.locator("#popC_ddlTipCom").count() > 0:
                    pagina.locator("#popC_ddlTipCom").wait_for(
                        state="visible", timeout=2000
                    )
                    pagina.bring_to_front()
                    log("Editor de comentário localizado na página.")
                    return pagina, pagina

                for frame in pagina.frames:
                    try:
                        campo_tipo = frame.locator("#popC_ddlTipCom")
                        if campo_tipo.count() == 0:
                            continue

                        campo_tipo.wait_for(state="visible", timeout=2000)
                        pagina.bring_to_front()
                        log("Frame do comentário localizado com sucesso.")
                        return pagina, frame
                    except Exception as erro_frame:
                        ultimo_erro = erro_frame
            except Exception as erro_pagina:
                ultimo_erro = erro_pagina

        page.wait_for_timeout(300)

    detalhe = f" Último erro: {ultimo_erro}" if ultimo_erro else ""
    raise RuntimeError(
        "O popup/frame de comentário não foi localizado após clicar em Comentários."
        + detalhe
    )


# ================================================================
# PREENCHER COMENTÁRIO
# ================================================================

def preencher_comentario(
    frame,
    tipo,
    texto,
    imagem_base64=None,
):

    log("")
    log("============================================")
    log("PREENCHENDO COMENTÁRIO")
    log("============================================")

    log(
        f"Tipo recebido: {tipo}"
    )

    log(
        f"Texto recebido: {len(texto)} caracteres"
    )

    log(
        "Imagem recebida: "
        + (
            "SIM"
            if imagem_base64
            else "NÃO"
        )
    )

    if imagem_base64:

        log(
            f"Tamanho Base64 recebido: "
            f"{len(imagem_base64)} caracteres"
        )

    # ============================================================
    # 1. SELECIONAR TIPO
    # ============================================================

    select = frame.locator(
        "#popC_ddlTipCom"
    )

    select.wait_for(
        state="visible",
        timeout=10000,
    )

    select.select_option(
        tipo
    )

    log(
        "Tipo de comentário selecionado."
    )

    # ============================================================
    # POSTBACK AJAX
    # ============================================================

    log(
        "Aguardando atualização do E-Desk..."
    )

    time.sleep(2)

    # ============================================================
    # 2. AGUARDAR EDITOR
    # ============================================================

    editor_iframe = frame.locator(
        "#ctl00_popC_rdeCom_contentIframe"
    )

    editor_iframe.wait_for(
        state="visible",
        timeout=15000,
    )

    log(
        "Iframe do Telerik encontrado."
    )

    # ============================================================
    # 3. PREPARAR TEXTO
    # ============================================================

    marcador_html = "[[EDESK_HTML]]"
    texto_recebido = texto or ""
    eh_html_pronto = texto_recebido.startswith(marcador_html)

    if eh_html_pronto:
        # HTML já foi montado pelo editor Flutter.
        # O marcador é apenas de transporte e não entra no E-Desk.
        texto_html = texto_recebido[len(marcador_html):]
    else:
        # Compatibilidade com chamadas antigas de texto simples.
        texto_html = html.escape(texto_recebido)
        texto_html = (
            texto_html
            .replace("\r\n", "<br>")
            .replace("\n", "<br>")
            .replace("\r", "<br>")
        )

    # ============================================================
    # 4. PREPARAR IMAGEM
    # ============================================================

    imagem_html = ""

    if imagem_base64 and not eh_html_pronto:

        try:

            imagem = (
                imagem_base64
                .strip()
            )

            if imagem.startswith(
                "data:"
            ):

                if "," not in imagem:

                    raise RuntimeError(
                        "Imagem Base64 possui prefixo data: "
                        "mas está sem os dados."
                    )

                prefixo, dados = (
                    imagem.split(
                        ",",
                        1,
                    )
                )

                mime = (
                    prefixo
                    .split(";")[0]
                    .replace(
                        "data:",
                        "",
                    )
                    .strip()
                )

                if not mime:

                    mime = "image/png"

            else:

                dados = imagem

                mime = "image/png"

            dados = (
                dados
                .replace(
                    "\r",
                    "",
                )
                .replace(
                    "\n",
                    "",
                )
                .replace(
                    " ",
                    "",
                )
            )

            imagem_html = (
                "<br>"
                f'<img '
                f'src="data:{mime};base64,{dados}" '
                f'alt="" '
                f'style="max-width:100%;height:auto;" '
                f'>'
            )

            log(
                "Imagem preparada para o RadEditor."
            )

            log(
                f"Tipo MIME: {mime}"
            )

            log(
                f"Tamanho dos dados da imagem: "
                f"{len(dados)} caracteres"
            )

        except Exception as erro:

            log(
                f"ERRO preparando imagem: {erro}"
            )

            raise

    # ============================================================
    # 5. HTML FINAL
    #
    # PRIMEIRO A IMAGEM
    # DEPOIS O TEXTO
    # ============================================================

    if eh_html_pronto:
        # As imagens já estão incorporadas no documento na posição correta.
        html_final = texto_html
    else:
        html_final = imagem_html + "<br>" + texto_html

    log(
        f"HTML final preparado: "
        f"{len(html_final)} caracteres"
    )

    log(
        f"HTML possui imagem: "
        f"{'<img' in html_final.lower()}"
    )

    # ============================================================
    # 6. RADEDITOR
    # ============================================================

    resultado = frame.evaluate(
        """
        (html) => {

            try {

                const editor =
                    window.$find(
                        "ctl00_popC_rdeCom"
                    );

                if (!editor) {

                    return {
                        sucesso: false,
                        erro:
                            "Objeto Telerik RadEditor não encontrado."
                    };
                }

                editor.set_html(html);

                return {
                    sucesso: true,
                    metodo:
                        "RadEditor.set_html",
                    html:
                        editor.get_html()
                };

            } catch (e) {

                return {
                    sucesso: false,
                    erro: String(e)
                };
            }
        }
        """,
        html_final,
    )

    # IMPORTANTE:
    # Não imprimir resultado inteiro.
    # Ele contém a imagem Base64.

    log(
        "Resultado RadEditor: "
        f"sucesso={resultado.get('sucesso')} "
        f"metodo={resultado.get('metodo')}"
    )

    html_resultado = (
        resultado.get(
            "html",
            "",
        )
        or ""
    )

    log(
        f"HTML retornado pelo RadEditor: "
        f"{len(html_resultado)} caracteres"
    )

    log(
        "Imagem presente no HTML retornado: "
        + (
            "SIM"
            if "<img" in html_resultado.lower()
            else "NÃO"
        )
    )

    if not resultado.get(
        "sucesso",
        False,
    ):

        raise RuntimeError(
            "Não foi possível preencher o RadEditor: "
            + str(
                resultado.get(
                    "erro",
                    "",
                )
            )
        )

    # ============================================================
    # 7. ATUALIZAR TEXTAREA OCULTO
    # ============================================================

    try:

        hidden = frame.locator(
            "#ctl00_popC_rdeComContentHiddenTextarea"
        )

        hidden.wait_for(
            state="attached",
            timeout=5000,
        )

        hidden.evaluate(
            """
            (element, html) => {

                element.value = html;

                element.dispatchEvent(
                    new Event(
                        "input",
                        {
                            bubbles: true
                        }
                    )
                );

                element.dispatchEvent(
                    new Event(
                        "change",
                        {
                            bubbles: true
                        }
                    )
                );
            }
            """,
            html_final,
        )

        log(
            "Textarea oculto atualizado."
        )

    except Exception as erro:

        log(
            f"Aviso no textarea oculto: {erro}"
        )

    # ============================================================
    # 8. VALIDAR RADEDITOR
    # ============================================================

    time.sleep(1)

    try:

        validacao = frame.evaluate(
            """
            () => {

                const editor =
                    window.$find(
                        "ctl00_popC_rdeCom"
                    );

                if (!editor) {

                    return {
                        html: "",
                        texto: ""
                    };
                }

                return {
                    html:
                        editor.get_html(),
                    texto:
                        editor.get_text()
                };
            }
            """
        )

        conteudo_editor = (
            validacao.get(
                "html",
                "",
            )
            or ""
        )

        texto_editor = (
            validacao.get(
                "texto",
                "",
            )
            or ""
        )

        log(
            "============================================"
        )

        log(
            "VALIDAÇÃO DO RADEDITOR"
        )

        log(
            f"HTML: "
            f"{len(conteudo_editor)} caracteres"
        )

        log(
            f"Texto: "
            f"{texto_editor[:500]!r}"
        )

        log(
            "Imagem presente no HTML: "
            + (
                "SIM"
                if "<img" in conteudo_editor.lower()
                else "NÃO"
            )
        )

        log(
            "============================================"
        )

        if not conteudo_editor.strip():

            raise RuntimeError(
                "O RadEditor ficou vazio após o preenchimento."
            )

        if imagem_base64:

            if "<img" not in (
                conteudo_editor.lower()
            ):

                raise RuntimeError(
                    "A imagem foi recebida pelo Python, "
                    "mas não apareceu no HTML do RadEditor."
                )

    except Exception as erro:

        log(
            f"Erro validando RadEditor: {erro}"
        )

        raise

    # ============================================================
    # 9. VALIDAR VISUALMENTE O IFRAME
    # ============================================================

    try:

        editor_frame = frame.frame_locator(
            "#ctl00_popC_rdeCom_contentIframe"
        )

        body = editor_frame.locator(
            "body"
        )

        texto_visual = body.inner_text(
            timeout=5000
        )

        log(
            f"Texto visível no editor: "
            f"{texto_visual[:500]!r}"
        )

        quantidade_imagens = (
            editor_frame
            .locator("img")
            .count()
        )

        log(
            f"Imagens visíveis no editor: "
            f"{quantidade_imagens}"
        )

        if imagem_base64:

            if quantidade_imagens == 0:

                raise RuntimeError(
                    "A imagem não está visível dentro "
                    "do editor do E-Desk."
                )

    except Exception as erro:

        log(
            f"Aviso/erro validando conteúdo visual: {erro}"
        )

        raise

    log("")
    log(
        "============================================"
    )

    log(
        "COMENTÁRIO PREENCHIDO E VALIDADO"
    )

    log(
        "Texto + imagem estão dentro do RadEditor."
    )

    log(
        "============================================"
    )


# ================================================================
# SALVAR COMENTÁRIO
# ================================================================

def salvar_comentario(frame, pagina):

    log("")
    log("============================================")
    log("SALVANDO COMENTÁRIO")
    log("============================================")

    botao_salvar = frame.locator(
        "#popC_BtAtu"
    )

    if botao_salvar.count() == 0:

        raise RuntimeError(
            "Botão Salvar do comentário não encontrado."
        )

    botao_salvar.wait_for(
        state="visible",
        timeout=10000,
    )

    log(
        "Botão Salvar encontrado."
    )

    requisicoes_salvar = set()
    respostas_salvar = []

    def registrar_requisicao(requisicao):
        if requisicao.method != "POST":
            return

        dados_post = parse_qs(
            requisicao.post_data or "",
            keep_blank_values=True,
        )
        targets = dados_post.get("__EVENTTARGET", [])
        controles = [
            chave
            for chave in dados_post
            if "BtAtu" in chave
        ]

        if not any("BtAtu" in alvo for alvo in targets) and not controles:
            return

        chave_requisicao = (
            requisicao.url,
            requisicao.post_data or "",
        )
        requisicoes_salvar.add(chave_requisicao)
        log("POST do botão Salvar do comentário detectado.")

    def registrar_resposta(resposta):
        chave_requisicao = (
            resposta.request.url,
            resposta.request.post_data or "",
        )
        if chave_requisicao in requisicoes_salvar:
            respostas_salvar.append(resposta)

    pagina.on("request", registrar_requisicao)
    pagina.on("response", registrar_resposta)
    try:
        botao_salvar.click(timeout=15000)

        inicio = time.time()
        while not respostas_salvar and time.time() - inicio < 20:
            # Saving may close the comment popup. Pump browser events through
            # a surviving page instead of waiting on the disposed popup.
            waiting_page = pagina
            if pagina.is_closed():
                waiting_page = next((p for p in pagina.context.pages if not p.is_closed()), None)
                if waiting_page is None:
                    raise RuntimeError('A sessão do navegador fechou antes da resposta do comentário.')
            waiting_page.wait_for_timeout(250)

        if not respostas_salvar:
            raise RuntimeError(
                "Nenhuma resposta ao POST do botão Salvar do comentário "
                "foi observada. O bot não repetirá o envio para evitar "
                "duplicidade."
            )

        resposta = respostas_salvar[-1]
        if not resposta.ok:
            raise RuntimeError(
                "O E-Desk retornou HTTP "
                f"{resposta.status} ao salvar o comentário."
            )

        try:
            texto_resposta = resposta.text()
        except PlaywrightError:
            # A successful save response can execute window.close(), disposing
            # its body before Playwright reads it. Keep the observed exact Save
            # response; never click Save again just to retrieve that body.
            if not pagina.is_closed():
                raise
            texto_resposta = ''
            log('A janela do comentário fechou após a resposta do Salvar. Continuando sem repetir o comentário.')
        if "|error|" in texto_resposta.lower():
            raise RuntimeError(
                "O E-Desk retornou erro ASP.NET ao salvar o comentário: "
                f"{texto_resposta[:500]}"
            )

        log(
            "Resposta do E-Desk ao salvamento recebida: "
            f"HTTP {resposta.status}."
        )
        log(
            "A resposta HTTP não comprova, sozinha, a persistência "
            "do comentário."
        )
    finally:
        pagina.remove_listener("request", registrar_requisicao)
        pagina.remove_listener("response", registrar_resposta)


# ================================================================
# MODO TESTE
# ================================================================

def modo_teste(
    page,
    context,
):

    log("")
    log("============================================")
    log("MODO TESTE")
    log("============================================")

    log(
        "O navegador permanecerá aberto."
    )

    log(
        "O comentário foi apenas preenchido."
    )

    log(
        "Nenhum comentário será salvo."
    )

    log(
        "Para encerrar, feche o navegador."
    )

    log(
        "============================================"
    )

    while True:

        try:

            # ----------------------------------------------------
            # PÁGINA PRINCIPAL FECHADA
            # ----------------------------------------------------

            if page.is_closed():

                log(
                    "Página principal fechada."
                )

                break

            # ----------------------------------------------------
            # VERIFICAR PÁGINAS ABERTAS
            # ----------------------------------------------------

            paginas_abertas = [
                pagina
                for pagina in context.pages
                if not pagina.is_closed()
            ]

            if not paginas_abertas:

                log(
                    "Nenhuma página do navegador está aberta."
                )

                break

            time.sleep(0.5)

        except Exception as erro:

            log(
                f"Navegador encerrado: {erro}"
            )

            break

    # ============================================================
    # IMPORTANTE
    #
    # NÃO chamamos context.close() aqui.
    #
    # O with sync_playwright() do main()
    # será responsável pelo encerramento.
    # ============================================================

    log(
        "Modo teste encerrado."
    )

    log(
        "Retornando normalmente para o main."
    )

    return


# ================================================================
# MAIN
# ================================================================

def main(*, percentage_only=False):

    log("")
    log("============================================")
    log("E-DESK BOT")
    log("============================================")
    log("")

    # ============================================================
    # REQUEST
    # ============================================================

    dados = carregar_request()
    credenciais = obter_credenciais_edesk(dados)

    solicitacao = extrair_solicitacao(
        dados
    )

    id_trabalho = extrair_id_trabalho(
        dados
    )

    # ============================================================
    # DADOS DO COMENTÁRIO
    # ============================================================

    url = obter_url(
        dados
    )

    percentual = parse_percentage(dados.get('percentualRealizado'))

    tipo = obter_tipo_comentario(
        dados
    )

    texto = obter_texto(
        dados
    )

    imagem_base64 = (
        obter_imagem_base64(
            dados
        )
    )

    enviar = bool(
        dados.get(
            "enviar",
            False,
        )
    )
    if percentage_only and (percentual is None or not enviar):
        raise ValueError('Informe a porcentagem e confirme a atualização do trabalho.')

    # ============================================================
    # LOG DOS DADOS
    # ============================================================

    log(
        f"Solicitação recebida: {solicitacao}"
    )

    log(
        f"ID Trabalho recebido: {id_trabalho}"
    )

    log(
        f"URL recebida: {url}"
    )

    log(
        f"Tipo: {tipo}"
    )

    log(
        f"Enviar: {enviar}"
    )

    log(
        f"Tamanho do texto: "
        f"{len(texto)} caracteres"
    )

    log(
        "Imagem recebida: "
        + (
            "SIM"
            if imagem_base64
            else "NÃO"
        )
    )

    if imagem_base64:

        log(
            f"Tamanho Base64 da imagem: "
            f"{len(imagem_base64)} caracteres"
        )

    # ============================================================
    # PLAYWRIGHT
    # ============================================================

    with sync_playwright() as playwright:

        log("")
        log(
            "Iniciando Chromium..."
        )

        context = (
            playwright.chromium
            .launch_persistent_context(
                user_data_dir=str(
                    PROFILE_PATH
                ),
                headless=HEADLESS,
                args=[
                    "--start-maximized",
                ],
                viewport=None,
            )
        )

        restore_session_cookies(context)

        log(
            "Chromium iniciado."
        )

        # ========================================================
        # PÁGINA PRINCIPAL
        # ========================================================

        if context.pages:
            page = context.pages[0]
        else:
            page = context.new_page()

        # O monitor precisa existir antes de qualquer navegação.
        instalar_monitor_requests(page)

        # ========================================================
        # REUTILIZAR SESSÃO E-DESK
        # ========================================================

        guid_existente = obter_guid_da_url(
            page.url
        )

        autenticado = (
            "/Portal/PortalAtendente.aspx" in (page.url or "")
            or bool(guid_existente)
        )

        if not autenticado:

            log("")
            log("============================================================")
            log("ABRINDO E-DESK - PRIMEIRA VEZ NESTA SESSÃO")
            log("============================================================")
            log(f"URL inicial: {url}")

            page.goto(
                url,
                wait_until="domcontentloaded",
                timeout=60000,
            )

            log(
                f"URL após abertura: {page.url}"
            )

            aguardar_login(
                page,
                credenciais=credenciais,
            )

        else:

            log("")
            log("============================================================")
            log("SESSÃO E-DESK JÁ AUTENTICADA - REUTILIZANDO")
            log("============================================================")
            log(f"URL reutilizada: {page.url}")

        # ========================================================
        # GUID DA SESSÃO
        # ========================================================

        save_session_cookies(context)

        guid_sessao = obter_guid_da_url(
            page.url
        )

        if not guid_sessao:
            raise RuntimeError(
                "Não foi possível obter o GUID da sessão após o login."
            )

        log(
            f"GUID da sessão: {guid_sessao}"
        )

        # ========================================================
        # ACESSAR A GRID NA MESMA PÁGINA AUTENTICADA
        #
        # Este é o mesmo fluxo utilizado pelo edesk_horas.py.
        # Não criamos uma nova aba aqui, pois a Grid do E-Desk
        # precisa ser carregada no mesmo ciclo da página
        # autenticada para que os registros sejam populados.
        # ========================================================

        page.bring_to_front()

        acessar_minha_grid(
            page,
            guid_sessao,
        )

        # ========================================================
        # The request search is ready; the result table may be absent until
        # a search is submitted. The validated search below waits for results.

        log("")
        log("============================================")
        log("GRID PRONTA")
        log("============================================")
        log(f"URL DA GRID: {page.url}")

        # ========================================================
        # VALIDAR SOLICITAÇÃO
        # ========================================================

        if not solicitacao:

            raise RuntimeError(
                "A solicitação não foi informada."
            )

        # ========================================================
        # LOCALIZAR SOLICITAÇÃO
        # ========================================================

        try:
            pagina_grid, linha, preaberta = localizar_solicitacao_validada(
                page, context, solicitacao)
            if pagina_grid is None or (linha is None and preaberta is None):
                raise RuntimeError("Request search returned no matching result")
        except Exception as error:
            raise RuntimeError("EDESK_COMMENT_REQUEST_NOT_FOUND") from error
        page = abrir_solicitacao_para_comentario(
            pagina_grid, context, linha, solicitacao, preaberta)
        url_solicitacao_comentario = page.url

        if percentage_only:
            update_percentage_after_comment(page, context, url_solicitacao_comentario,
                                            solicitacao, id_trabalho, percentual)
            from send_progress import completed
            completed('percentual')
            print(json.dumps({'ok': True, 'operation': 'percentual',
                              'percentual': str(percentual),
                              'message': f'Percentual {percentual}% confirmado no trabalho. Nenhum comentário foi publicado.'}, ensure_ascii=False), flush=True)
            return 0

        # ========================================================
        # ABRIR COMENTÁRIO
        # ========================================================

        pagina_comentario, frame = (
            abrir_comentario(
                page,
                context,
            )
        )

        # ========================================================
        # PREENCHER COMENTÁRIO
        # ========================================================

        preencher_comentario(
            frame,
            tipo,
            texto,
            imagem_base64,
        )

        # ========================================================
        # SE ENVIAR = TRUE
        # ========================================================

        if enviar:

            def salvar_percentual():
                if percentual is None:
                    return
                log('Comentário salvo. Abrindo trabalho apenas para atualizar %Realizado.')
                update_percentage_after_comment(
                    page, context, url_solicitacao_comentario,
                    solicitacao, id_trabalho, percentual)
                log('Percentual confirmado depois de recarregar o trabalho.')

            try:
                save_comment_then_percentage(
                    lambda: salvar_comentario(frame, pagina_comentario),
                    salvar_percentual,
                )
            except RuntimeError as error:
                if 'EDESK_PERCENTAGE_PENDING' in str(error):
                    print(json.dumps({'ok': False, 'operation': 'comentarios',
                        'commentSaved': True, 'percentageConfirmed': False,
                        'message': 'Comentário salvo; porcentagem não confirmada. Envie somente a porcentagem, sem repetir o comentário.'},
                        ensure_ascii=False), flush=True)
                raise
            print(json.dumps({'ok': True, 'operation': 'comentarios',
                'commentSaved': True, 'percentageConfirmed': percentual is not None,
                'percentual': str(percentual) if percentual is not None else None},
                ensure_ascii=False), flush=True)
            from send_progress import completed
            completed('comment')

            log("")
            log("============================================")
            log("OPERAÇÃO CONCLUÍDA")
            log("============================================")

            log(
                "O E-Desk respondeu ao pedido de salvamento do comentário."
            )

            log(
                "O conteúdo do comentário foi enviado no POST."
            )

            log(
                "============================================"
            )

            time.sleep(3)

            log("")
            log("============================================")
            log("PROCESSO PYTHON FINALIZADO")
            log("============================================")

            return

        # ========================================================
        # TESTE
        # ========================================================

        log("")
        log("============================================")
        log("TESTE CONCLUÍDO")
        log("============================================")

        log(
            "Solicitação encontrada."
        )

        log(
            "Uma única tela de trabalho foi utilizada."
        )

        log(
            "Comentário aberto."
        )

        log(
            "Tipo recebido do aplicativo."
        )

        log(
            "Texto recebido do aplicativo."
        )

        log(
            "Imagem recebida do aplicativo."
            if imagem_base64
            else "Nenhuma imagem recebida."
        )

        log(
            "Texto + imagem foram preenchidos "
            "no RadEditor."
        )

        log(
            "Comentário NÃO foi salvo porque enviar=false."
        )

        log(
            "============================================"
        )

        log("EDESK_TEST_READY")

        # ========================================================
        # CORREÇÃO IMPORTANTE:
        #
        # Passamos PAGE + CONTEXT.
        # ========================================================

        modo_teste(
            pagina_comentario,
            context,
        )

        log("")
        log("============================================")
        log("MODO TESTE FINALIZADO")
        log("============================================")


# ================================================================
# EXECUÇÃO
# ================================================================

if __name__ == "__main__":

    try:

        main()

        # --------------------------------------------------------
        # Se chegou aqui, o Python terminou normalmente.
        # --------------------------------------------------------

        log(
            "Processo Python finalizado normalmente."
        )

        sys.exit(0)

    except KeyboardInterrupt:

        log(
            "Processo interrompido pelo usuário."
        )

        sys.exit(1)

    except Exception as erro:

        log(
            f"ERRO: {erro}"
        )

        try:

            import traceback

            traceback.print_exc()

        except Exception:

            pass

        sys.exit(1)
