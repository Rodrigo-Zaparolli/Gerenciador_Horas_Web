import sys
import json
import time
import html
import re
import os

from pathlib import Path
from urllib.parse import (
    urlparse,
    parse_qs,
    unquote,
    urlencode,
)

from playwright.sync_api import sync_playwright
from send_progress import observe_log, hour_event, stage
from hour_receipt import read_hours, deliver_hours, GRID_DIAGNOSTIC_SCRIPT
from work_selection import resolve_work_selection

from config import restore_session_cookies, save_session_cookies
from config import (
    PROFILE_DIR,
    SCREENSHOTS_DIR,
    LOGS_DIR,
)

BASE_DIR = Path(__file__).resolve().parent

PROFILE_PATH = BASE_DIR / PROFILE_DIR
SCREENSHOTS_PATH = BASE_DIR / SCREENSHOTS_DIR
LOGS_PATH = BASE_DIR / LOGS_DIR

PROFILE_PATH.mkdir(parents=True, exist_ok=True)
SCREENSHOTS_PATH.mkdir(parents=True, exist_ok=True)
LOGS_PATH.mkdir(parents=True, exist_ok=True)

RUN_LOG_PATH = LOGS_PATH / (
    f"edesk_horas_{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}.log"
)

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

def log(mensagem):
    observe_log(mensagem)
    linha = f"[E-Desk][Horas] {mensagem}"
    print(linha, flush=True)
    with RUN_LOG_PATH.open("a", encoding="utf-8") as arquivo:
        arquivo.write(linha + "\n")

def carregar_request():
    if len(sys.argv) < 2:
        raise RuntimeError("Nenhum arquivo request.json foi informado.")

    request_path = Path(sys.argv[1])
    log(f"Request recebido: {request_path}")

    if not request_path.exists():
        raise RuntimeError(f"Request não encontrado: {request_path}")

    with request_path.open("r", encoding="utf-8") as arquivo:
        dados = json.load(arquivo)

    dados_log = dict(dados)
    credenciais_log = dados_log.get("edeskCredenciais")

    if isinstance(credenciais_log, dict):
        credenciais_log = dict(credenciais_log)
        if "senha" in credenciais_log:
            credenciais_log["senha"] = "*** OCULTA ***"
        if "email" in credenciais_log:
            credenciais_log["email"] = "*** OCULTO ***"
        dados_log["edeskCredenciais"] = credenciais_log

    log("")
    log("============================================================")
    log("CONTEÚDO DO REQUEST.JSON")
    log("============================================================")

    try:
        log(json.dumps(dados_log, ensure_ascii=False, indent=2))
    except Exception as erro:
        log(f"Não foi possível exibir o JSON formatado: {erro}")

    log("============================================================")

    trabalhos = dados.get("trabalhos", [])

    if isinstance(trabalhos, list) and trabalhos:
        log("")
        log("============================================================")
        log("TRABALHOS RECEBIDOS")
        log("============================================================")
        log(f"Quantidade de trabalhos: {len(trabalhos)}")

        for indice_trabalho, trabalho in enumerate(trabalhos, start=1):
            if not isinstance(trabalho, dict):
                continue

            solicitacao = str(trabalho.get("solicitacao", "") or "").strip()
            id_trabalho = str(trabalho.get("idTrabalho", trabalho.get("id_trabalho", ""),) or "").strip()
            horas = trabalho.get("horas", [])

            if not isinstance(horas, list):
                horas = []

            log("")
            log(f"---------------- TRABALHO {indice_trabalho} ----------------")
            log(f"SOLICITAÇÃO: {solicitacao}")
            log(f"ID TRABALHO RELATIVO: {id_trabalho}")
            log(f"QUANTIDADE DE HORAS: {len(horas)}")

            for indice_hora, hora in enumerate(horas, start=1):
                log("")
                log(f"HORA {indice_hora}:")
                try:
                    log(json.dumps(hora, ensure_ascii=False, indent=2))
                except Exception:
                    log(str(hora))

                if isinstance(hora, dict):
                    descritivo = obter_descritivo_hora(hora)
                    log(f"DESCRITIVO: {descritivo or '[NÃO INFORMADO]'}")

        log("============================================================")
        log("")
    else:
        horas = dados.get("horas", [])
        log("")
        log("============================================================")
        log("DADOS DE HORAS RECEBIDOS")
        log("============================================================")
        log(f"Tipo de 'horas': {type(horas).__name__}")

        if isinstance(horas, list):
            log(f"Quantidade de registros em 'horas': {len(horas)}")
            for indice, hora in enumerate(horas, start=1):
                log("")
                log(f"---------------- HORA {indice} ----------------")
                try:
                    log(json.dumps(hora, ensure_ascii=False, indent=2))
                except Exception:
                    log(str(hora))

                if isinstance(hora, dict):
                    descritivo = obter_descritivo_hora(hora)
                    log(f"DESCRITIVO: {descritivo or '[NÃO INFORMADO]'}")
        else:
            log("O campo 'horas' NÃO é uma lista.")

        log("============================================================")
        log("")

    return dados

def obter_url(dados):
    url = str(dados.get("url", "")).strip()
    if not url:
        raise RuntimeError("A URL do E-Desk não foi informada.")
    return url

def extrair_id_trabalho(dados):
    return str(dados.get("idTrabalho", "")).strip()

def extrair_solicitacao(dados):
    return str(dados.get("solicitacao", "")).strip()

def extrair_horas(dados):
    horas = dados.get("horas", [])
    if not isinstance(horas, list):
        return []
    return horas

def extrair_trabalhos(dados):
    trabalhos = dados.get("trabalhos", [])
    resultado = []

    if isinstance(trabalhos, list) and trabalhos:
        for trabalho in trabalhos:
            if not isinstance(trabalho, dict):
                continue
            solicitacao = str(trabalho.get("solicitacao", "") or "").strip()
            id_trabalho = str(trabalho.get("idTrabalho", trabalho.get("id_trabalho", ""),) or "").strip()
            horas = trabalho.get("horas", [])
            if not isinstance(horas, list):
                horas = []

            resultado.append({
                "solicitacao": solicitacao,
                "id_trabalho": id_trabalho,
                "horas": horas,
            })
        return resultado

    solicitacao = extrair_solicitacao(dados)
    id_trabalho = extrair_id_trabalho(dados)
    horas = extrair_horas(dados)

    if solicitacao and id_trabalho:
        resultado.append({
            "solicitacao": solicitacao,
            "id_trabalho": id_trabalho,
            "horas": horas,
        })

    return resultado

def obter_descritivo_hora(hora):
    if not isinstance(hora, dict):
        return ""

    campos = [
        "descritivo", "descricao", "descrição", "description",
        "atividade", "motivo", "observacao", "observação",
    ]

    for campo in campos:
        valor = hora.get(campo, "")
        if valor is None:
            continue
        valor = str(valor).strip()
        if valor:
            return valor

    return ""

def limpar_descritivo_hora(descritivo, data):
    descritivo = str(descritivo or "").strip()
    data = str(data or "").strip()

    if not descritivo:
        return ""

    descritivo = re.sub(r"^\s*-\s*", "", descritivo).strip()

    if data:
        padrao_data = re.escape(data)
        descritivo = re.sub(rf"^\s*{padrao_data}\s*:?\s*-?\s*", "", descritivo, count=1).strip()

    descritivo = re.sub(r"^\s*\d{2}/\d{2}/\d{4}\s*:?\s*-?\s*", "", descritivo, count=1).strip()

    return descritivo

def obter_data_hora(hora):
    if not isinstance(hora, dict):
        return ""

    for campo in ["data", "date", "dt"]:
        valor = hora.get(campo, "")
        if valor is None:
            continue
        valor = str(valor).strip()
        if valor:
            return valor

    return ""

def obter_inicio_hora(hora):
    if not isinstance(hora, dict):
        return ""

    for campo in ["inicio", "início", "horaInicio", "hora_inicio", "start"]:
        valor = hora.get(campo, "")
        if valor is None:
            continue
        valor = str(valor).strip()
        if valor:
            return valor

    return ""

def obter_fim_hora(hora):
    if not isinstance(hora, dict):
        return ""

    for campo in ["fim", "horaFim", "hora_fim", "end"]:
        valor = hora.get(campo, "")
        if valor is None:
            continue
        valor = str(valor).strip()
        if valor:
            return valor

    return ""

def obter_modo_envio(dados):
    valor = dados.get("enviar", False)
    if isinstance(valor, bool):
        return valor
    texto = str(valor).strip().lower()
    return texto in ["true", "1", "sim", "yes", "envio"]

def obter_manter_navegador_aberto(dados):
    valor = dados.get("manterNavegadorAberto", False)
    if isinstance(valor, bool):
        return valor
    texto = str(valor).strip().lower()
    return texto in ["true", "1", "sim", "yes"]

def normalizar_texto_resposta(texto):
    if not texto:
        return ""
    texto = str(texto)
    texto = html.unescape(texto)
    texto = texto.replace("\\/", "/")
    texto = texto.replace("\\u0026", "&")
    texto = texto.replace("\\x26", "&")

    for _ in range(5):
        novo = unquote(texto)
        if novo == texto:
            break
        texto = novo

    return texto

def obter_guid_da_url(url):
    try:
        parametros = parse_qs(urlparse(url).query)
        return parametros.get("GUID", [""])[0]
    except Exception:
        return ""

def extrair_dados_url(url):
    resultado = {
        "url": url,
        "pagina": "",
        "guid": "",
        "solicitacao": "",
        "cmd": "",
        "id_trabalho": "",
        "projeto": "",
        "atividade": "",
        "cmdprj": "",
    }
    try:
        partes = urlparse(url)
        resultado["pagina"] = partes.path
        parametros = parse_qs(partes.query)
        resultado["guid"] = parametros.get("GUID", [""])[0]
        resultado["solicitacao"] = parametros.get("solicitacao", [""])[0]
        resultado["cmd"] = parametros.get("cmd", [""])[0]
        resultado["id_trabalho"] = parametros.get("id_trabalho", [""])[0]
        if not resultado["id_trabalho"]:
            resultado["id_trabalho"] = parametros.get("idTrabalho", [""])[0]
    except Exception as erro:
        resultado["erro"] = str(erro)
    return resultado

def extrair_dados_url_trabalho(url):
    return extrair_dados_url(url)

def nome_pagina(url):
    try:
        return urlparse(url).path.split("/")[-1].lower()
    except Exception:
        return ""

def eh_solicitacao(url):
    return nome_pagina(url) == "solicitacao.aspx"

def eh_trabalho(url):
    return nome_pagina(url) == "trabalho.aspx"

def eh_trabalho_retroativo(url):
    return nome_pagina(url) == "trabalhoretroativo.aspx"

def instalar_monitor_navegacao(context):
    log("")
    log("============================================")
    log("INSTALANDO MONITOR DE NAVEGAÇÃO")
    log("============================================")

    def navegacao(frame):
        try:
            if frame.parent_frame is not None:
                return
            url = frame.url
            if not url:
                return
            pagina = nome_pagina(url)
            if pagina not in ["solicitacao.aspx", "trabalho.aspx", "trabalhoretroativo.aspx"]:
                return

            log("")
            log("****************************************")
            log("NAVEGAÇÃO E-DESK DETECTADA")
            log("****************************************")
            log(f"Página: {pagina}")
            log(f"URL: {url}")
            log("****************************************")
            log("")
        except Exception as erro:
            log(f"Erro no monitor de navegação: {erro}")

    context.on("framenavigated", navegacao)

def obter_credenciais_edesk(dados):
    credenciais = dados.get("edeskCredenciais")

    if not isinstance(credenciais, dict):
        email = str(dados.get("edeskEmail", "") or "").strip()
        senha = str(dados.get("edeskSenha", "") or "")
    else:
        email = str(credenciais.get("email", "") or "").strip()
        senha = str(credenciais.get("senha", "") or "")

    if not email:
        log("E-mail E-Desk não informado.")
        return None

    if not senha:
        log("Senha E-Desk não informada.")
        return None

    log("Credenciais E-Desk disponíveis para login automático.")
    log("E-mail disponível: SIM | [OCULTO]")
    log(f"Senha disponível: SIM | {len(senha)} caracteres")

    return {
        "email": email,
        "senha": senha,
    }

def localizar_elemento_visivel(page, seletores):
    for seletor in seletores:
        try:
            elementos = page.locator(seletor)
            quantidade = elementos.count()
            for indice in range(quantidade):
                elemento = elementos.nth(indice)
                try:
                    if elemento.is_visible():
                        return elemento
                except Exception:
                    pass
        except Exception:
            pass

    try:
        frames = list(page.frames)
    except Exception:
        frames = []

    for frame in frames:
        try:
            for seletor in seletores:
                elementos = frame.locator(seletor)
                quantidade = elementos.count()
                for indice in range(quantidade):
                    elemento = elementos.nth(indice)
                    try:
                        if elemento.is_visible():
                            return elemento
                    except Exception:
                        pass
        except Exception:
            pass

    return None

def login_confirmado(page):
    try:
        if "/Portal/PortalAtendente.aspx" in page.url:
            return True
    except Exception:
        pass

    try:
        for seletor in ["#cph1_BtCom", "#cph1_txtSol"]:
            elemento = page.locator(seletor)
            if elemento.count() > 0:
                try:
                    if elemento.first.is_visible(timeout=1000):
                        return True
                except Exception:
                    return True
    except Exception:
        pass

    return False

def tela_login_detectada(page):
    try:
        senha = localizar_elemento_visivel(page, SELETORES_SENHA_LOGIN)
        if senha is not None:
            return True
    except Exception:
        pass

    try:
        url = (page.url or "").lower()
        marcadores = [
            "promobid.promob.com",
            "identity.promob.com",
            "/authentications/signin",
            "/signin",
            "/login",
        ]
        return any(marcador in url for marcador in marcadores)
    except Exception:
        return False

def tentar_login_automatico(page, credenciais):
    if not credenciais:
        log("Login automático indisponível: nenhuma credencial cadastrada.")
        return False

    email = str(credenciais.get("email", "") or "").strip()
    senha = str(credenciais.get("senha", "") or "")

    if not email or not senha:
        log("Credenciais automáticas incompletas.")
        return False

    log("")
    log("============================================================")
    log("TENTANDO LOGIN AUTOMÁTICO DO PROMOB ID")
    log("============================================================")
    log(f"URL atual: {page.url}")

    campo_email = None
    inicio = time.time()

    while time.time() - inicio < 30:
        try:
            campo_email = localizar_elemento_visivel(page, SELETORES_EMAIL_LOGIN)
            if campo_email is not None:
                break
        except Exception:
            pass
        time.sleep(0.5)

    if campo_email is None:
        log("Campo de e-mail não encontrado para login automático.")
        return False

    try:
        campo_email.click()
        campo_email.fill(email)
        log("E-mail preenchido automaticamente.")
    except Exception as erro:
        log(f"Erro preenchendo e-mail: {erro}")
        return False

    campo_senha = None
    inicio = time.time()

    while time.time() - inicio < 30:
        try:
            campo_senha = localizar_elemento_visivel(page, SELETORES_SENHA_LOGIN)
            if campo_senha is not None:
                break
        except Exception:
            pass
        time.sleep(0.5)

    if campo_senha is None:
        log("Campo de senha não encontrado para login automático.")
        return False

    try:
        campo_senha.click()
        campo_senha.fill(senha)
        log("Senha preenchida automaticamente.")
    except Exception as erro:
        log(f"Erro preenchendo senha: {erro}")
        return False

    botao_entrar = None
    inicio = time.time()

    while time.time() - inicio < 20:
        try:
            botao_entrar = localizar_elemento_visivel(page, SELETORES_ENTRAR_LOGIN)
            if botao_entrar is not None:
                break
        except Exception:
            pass
        time.sleep(0.5)

    try:
        if botao_entrar is not None:
            log("Botão Entrar encontrado.")
            botao_entrar.click(force=True)
            log("Clique em Entrar executado.")
        else:
            log("Botão Entrar não encontrado. Tentando ENTER no campo de senha.")
            campo_senha.press("Enter")
    except Exception as erro:
        log(f"Erro enviando formulário de login: {erro}")
        return False

    log("Aguardando confirmação da autenticação...")
    inicio = time.time()
    ultimo_url = ""

    while time.time() - inicio < 40:
        try:
            url_atual = page.url
            if url_atual != ultimo_url:
                log(f"URL após login: {url_atual}")
                ultimo_url = url_atual

            if login_confirmado(page):
                log("LOGIN AUTOMÁTICO CONFIRMADO.")
                return True
        except Exception:
            pass
        time.sleep(1)

    log("LOGIN AUTOMÁTICO NÃO FOI CONFIRMADO.")
    return False

def aguardar_login(page, credenciais=None, timeout_segundos=300):
    log("")
    log("========================================")
    log("AUTENTICAÇÃO DO PROMOB")
    log("========================================")
    log("")

    if login_confirmado(page):
        log("Sessão E-Desk já autenticada.")
        return

    inicio = time.time()
    tentativa_automatica = False
    ultimo_url = ""

    while True:
        if time.time() - inicio > timeout_segundos:
            raise RuntimeError("Tempo limite de autenticação excedido.")

        try:
            url_atual = page.url
            if url_atual != ultimo_url:
                log(f"URL atual: {url_atual}")
                ultimo_url = url_atual
        except Exception:
            pass

        if login_confirmado(page):
            log("AUTENTICAÇÃO CONFIRMADA.")
            return

        if not tentativa_automatica and credenciais and tela_login_detectada(page):
            tentativa_automatica = True
            try:
                sucesso = tentar_login_automatico(page, credenciais)
                if sucesso:
                    return
            except Exception as erro:
                log(f"Erro no login automático: {erro}")
            log("Login automático não confirmado. Aguardando login manual como fallback.")

        time.sleep(1)

def acessar_minha_grid(page, guid=None):
    log("")
    log("============================================")
    log("ACESSANDO MINHA GRID")
    log("============================================")

    guid = str(guid or obter_guid_da_url(page.url) or "").strip()
    if not guid:
        raise RuntimeError("GUID da sessão do E-Desk não encontrado.")

    url_grid = f"https://promob.e-desk.com.br/Portal/ListaSolicitacao.aspx?GUID={guid}"
    log(f"Acessando Grid: {url_grid}")

    try:
        page.goto(url_grid, wait_until="domcontentloaded", timeout=60000)
    except Exception as erro:
        log(f"Aviso durante acesso à Grid: {erro}")

    page.locator("#cph1_txtSol").first.wait_for(state="visible", timeout=20000)
    log(f"URL atual da Grid: {page.url}")

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
            if not any(pagina in url for pagina in paginas_interesse):
                return
        except Exception:
            pass
    page.on("request", monitor_request)

def localizar_solicitacao(page, context, numero_solicitacao, atividade_alvo=""):
    numero_solicitacao = str(numero_solicitacao or "").strip()
    atividade_alvo = str(atividade_alvo or "").strip()

    log("")
    log("============================================")
    log("PESQUISANDO SOLICITAÇÃO NA GRID")
    log("============================================")
    log(f"Solicitação: {numero_solicitacao}")
    log(f"Atividade alvo: {atividade_alvo or '[NÃO INFORMADA]'}")

    seletor_tabela = "#ctl00_cph1_hgrSol_ctl00"

    # Guardamos o estado das páginas antes da pesquisa. O E-Desk pode manter
    # a Grid na página atual, abrir outra página ou navegar a página atual.
    paginas_antes = {id(p): (p.url or "") for p in context.pages if not p.is_closed()}

    try:
        campo = page.locator("#cph1_txtSol").first
        campo.wait_for(state="visible", timeout=20000)
        campo.fill("")
        campo.fill(numero_solicitacao)
        log("Número preenchido no campo Pesquisar.")

        botao = page.locator("#cph1_btnLocSol").first
        botao.wait_for(state="attached", timeout=20000)
        log("Executando pesquisa...")
        try:
            botao.click(force=True, timeout=10000)
        except Exception:
            # O clique pode ter enviado o postback antes de o Playwright
            # reportar uma falha. Não reenviamos a pesquisa com Enter, pois
            # isso pode abrir a mesma solicitação uma segunda vez.
            log(
                "O clique da pesquisa retornou erro; aguardando o resultado "
                "sem reenviar o formulário."
            )
    except Exception as erro:
        log(f"Erro ao pesquisar solicitação: {erro}")
        return None, None, None

    # O E-Desk pode manter o resultado na Grid OU abrir Solicitação.aspx
    # automaticamente ao pesquisar. Quando a Solicitação já foi aberta,
    # ela deve ser reaproveitada; não executamos um segundo clique na Grid.
    pagina_grid = None
    pagina_solicitacao_preaberta = None
    inicio = time.time()
    urls_vistas = set()

    while time.time() - inicio < 25:
        for pagina in list(context.pages):
            try:
                if pagina.is_closed():
                    continue

                url_atual = pagina.url or ""
                chave_url = f"{id(pagina)}|{url_atual}"
                if chave_url not in urls_vistas:
                    log(f"Página observada após pesquisa: {url_atual}")
                    urls_vistas.add(chave_url)

                if eh_solicitacao(url_atual):
                    pagina_nova = id(pagina) not in paginas_antes
                    pagina_navegou = (
                        id(pagina) in paginas_antes
                        and paginas_antes[id(pagina)] != url_atual
                    )
                    if pagina_nova or pagina_navegou:
                        pagina_solicitacao_preaberta = pagina
                        break

                tabela_candidata = pagina.locator(seletor_tabela).first
                if tabela_candidata.count() == 0:
                    continue

                texto_tabela = tabela_candidata.inner_text(timeout=1500)
                if numero_solicitacao not in texto_tabela:
                    continue

                pagina_grid = pagina
                # Examine também as abas seguintes: a pesquisa pode ter
                # aberto a solicitação enquanto a Grid continua visível.
            except Exception:
                continue

        if pagina_solicitacao_preaberta is not None:
            break
        if pagina_grid is not None:
            abas_carregando = any(
                id(p) not in paginas_antes
                and not p.is_closed()
                and (p.url or "") in ("", "about:blank")
                for p in context.pages
            )
            if not abas_carregando and time.time() - inicio >= 2:
                break
        time.sleep(0.4)

    if pagina_solicitacao_preaberta is not None:
        log(
            "A pesquisa abriu Solicitação.aspx automaticamente. "
            "A página será reutilizada sem novo clique na Grid."
        )
        pagina_solicitacao_preaberta._edesk_search_snapshot = paginas_antes
        return page, None, pagina_solicitacao_preaberta

    if pagina_grid is None:
        log(f"URL da página original após pesquisa: {page.url}")
        log("Nenhuma página com a Grid e a solicitação pesquisada foi encontrada.")
        return None, None, None

    if pagina_grid is not page:
        log("Resultado da pesquisa localizado em outra página do navegador.")
    elif paginas_antes.get(id(page), "") != (page.url or ""):
        log("A página original navegou durante a pesquisa e continuou sendo a Grid válida.")

    log(f"URL da Grid válida após pesquisa: {pagina_grid.url}")

    try:
        tabela = pagina_grid.locator(seletor_tabela).first
        tabela.wait_for(state="visible", timeout=15000)
    except Exception as erro:
        log(f"Grid válida não ficou visível após a pesquisa: {erro}")
        return None, None, None

    linhas = pagina_grid.locator(
        f"{seletor_tabela} tr.rgRow, {seletor_tabela} tr.rgAltRow"
    )
    candidatos = []

    for i in range(linhas.count()):
        linha = linhas.nth(i)
        try:
            texto_linha = linha.inner_text(timeout=2000).strip()
            celulas = linha.locator("td")
            numero_linha = ""
            if celulas.count() >= 2:
                numero_linha = celulas.nth(1).inner_text(timeout=1000).strip()
            if numero_linha == numero_solicitacao or numero_solicitacao in texto_linha:
                candidatos.append((i, linha, texto_linha))
                log(f"Candidato {len(candidatos)}: linha {i} | {texto_linha}")
        except Exception:
            continue

    if not candidatos:
        log("Tentando localizar a solicitação em todos os TRs...")
        todas = tabela.locator("tr")
        for i in range(todas.count()):
            linha = todas.nth(i)
            try:
                texto_linha = linha.inner_text(timeout=1500).strip()
                classe = (linha.get_attribute("class") or "").lower()
                if numero_solicitacao not in texto_linha:
                    continue
                if "rgheader" in classe or "rggroupheader" in classe or "rgfilterrow" in classe:
                    continue
                candidatos.append((i, linha, texto_linha))
            except Exception:
                continue

    if not candidatos:
        log(f"Solicitação {numero_solicitacao} não encontrada após usar Pesquisar.")
        return None, None, None

    def normalizar(valor):
        valor = str(valor or "").lower()
        trocas = {
            "á":"a", "à":"a", "ã":"a", "â":"a", "ä":"a",
            "é":"e", "è":"e", "ê":"e", "ë":"e",
            "í":"i", "ì":"i", "î":"i", "ï":"i",
            "ó":"o", "ò":"o", "õ":"o", "ô":"o", "ö":"o",
            "ú":"u", "ù":"u", "û":"u", "ü":"u", "ç":"c",
        }
        for origem, destino in trocas.items():
            valor = valor.replace(origem, destino)
        return re.sub(r"[^a-z0-9]+", " ", valor).strip()

    escolhido = None
    if atividade_alvo and len(candidatos) > 1:
        alvo = normalizar(atividade_alvo)
        for item in candidatos:
            if alvo and alvo in normalizar(item[2]):
                escolhido = item
                break

        if escolhido is None:
            palavras = [p for p in alvo.split() if len(p) >= 3]
            melhor = None
            melhor_pontos = -1
            for item in candidatos:
                texto_norm = normalizar(item[2])
                pontos = sum(1 for palavra in palavras if palavra in texto_norm)
                if pontos > melhor_pontos:
                    melhor_pontos = pontos
                    melhor = item
            if melhor is not None and melhor_pontos > 0:
                escolhido = melhor

    if escolhido is None:
        escolhido = candidatos[0]

    indice, linha, texto_linha = escolhido
    log("")
    log("LINHA ESCOLHIDA APÓS PESQUISA")
    log(f"Índice: {indice}")
    log(f"Texto: {texto_linha}")
    log(f"Ocorrências: {len(candidatos)}")
    return pagina_grid, linha, None


def abrir_trabalho_na_solicitacao(page, context, numero_solicitacao, id_trabalho):
    log("")
    log("=" * 60)
    log("ABRINDO TRABALHO NA ABA TRABALHOS")
    log("=" * 60)

    id_trabalho = str(id_trabalho or "").strip()
    if not id_trabalho:
        log("ID do trabalho não informado.")
        return None

    def wait_work_ui_ready():
        page.wait_for_load_state('domcontentloaded', timeout=15000)
        page.wait_for_function('''() => {
            const manager = window.Sys?.WebForms?.PageRequestManager?.getInstance?.();
            return document.readyState !== 'loading' && !manager?.get_isInAsyncPostBack?.();
        }''', timeout=15000)

    try:
        wait_work_ui_ready()
        table = page.locator('#cph1_gvwTra')
        if not table.count() or not table.first.is_visible():
            tabs = page.get_by_text(re.compile(r'^Trabalhos\s*(?:\(\d+\))?$'))
            deadline = time.monotonic() + 15
            visible_tabs = []
            while time.monotonic() < deadline:
                visible_tabs = [tab for tab in tabs.all() if tab.is_visible()]
                if visible_tabs:
                    break
                page.wait_for_timeout(100)
            if len(visible_tabs) != 1:
                raise RuntimeError('Aba Trabalhos ausente ou ambígua.')
            visible_tabs[0].click(timeout=15000)
        wait_work_ui_ready()
        table.first.wait_for(state='visible', timeout=15000)
    except Exception as error:
        raise RuntimeError('EDESK_WORK_TAB_NOT_OPENED') from error

    seletor_aba = "#cph1_rpvTrabalhos"
    try:
        aba = page.locator(seletor_aba).first
        aba.wait_for(state="visible", timeout=10000)
    except Exception as erro:
        log(f"Aba de trabalhos não visível: {erro}")
        return None

    tabela = aba.locator("#cph1_gvwTra").first
    try:
        tabela.wait_for(state="visible", timeout=10000)
    except Exception as erro:
        log(f"Tabela de trabalhos não visível: {erro}")
        return None

    alvo = None
    limite = time.monotonic() + 10
    while time.monotonic() < limite:
        wait_work_ui_ready()
        alvo = resolve_work_selection(tabela, id_trabalho)
        if alvo is not None:
            break
        page.wait_for_timeout(200)
    if alvo is None:
        log(f"Trabalho relativo {id_trabalho} nao localizado na tabela de trabalhos.")
        return None

    try:
        onclick = alvo.get_attribute("onclick") or alvo.get_attribute("href") or ""
    except Exception:
        onclick = ""

    log(f"POSTBACK ENCONTRADO: {onclick}")
    if not onclick:
        log("O elemento de seleção não possui onclick.")
        return None

    postback_match = re.search(r"__doPostBack\('([^']+)'\s*,\s*'([^']*)'\)", onclick)
    if postback_match:
        log(f"EVENT TARGET: {postback_match.group(1)}")
        log(f"EVENT ARGUMENT: {postback_match.group(2)}")

    log("Executando clique original do botão de seleção...")

    # Snapshot antes do clique: evita capturar Trabalho.aspx antigo de outro ciclo.
    paginas_antes = {id(p): (p.url or "") for p in context.pages if not p.is_closed()}
    url_solicitacao_antes = page.url or ""

    try:
        alvo.scroll_into_view_if_needed(timeout=5000)
    except Exception:
        pass

    try:
        # Let Playwright wait for an actionable control. Forcing the click can
        # hit a disabled/covered initial control before the Ajax page is ready.
        alvo.click(timeout=15000)
    except Exception as erro:
        log(f"Erro no clique do btnSelTra: {erro}")
        return None

    log("Clique executado.")
    log("Aguardando abertura de Trabalho.aspx...")

    inicio = time.time()
    urls_vistas = set()

    while time.time() - inicio < 30:
        for pagina in context.pages:
            try:
                if pagina.is_closed():
                    continue
                url_atual = pagina.url
                if url_atual not in urls_vistas:
                    log(f"URL durante abertura do trabalho: {url_atual}")
                    urls_vistas.add(url_atual)

                # Aceita somente a própria Solicitação que navegou para Trabalho
                # ou uma página nova criada por ESTE clique.
                pagina_nova = id(pagina) not in paginas_antes
                pagina_atual_navegou = (
                    pagina is page
                    and url_atual != url_solicitacao_antes
                )

                if eh_trabalho(url_atual) and (pagina_nova or pagina_atual_navegou):
                    if not validar_tela_trabalho(
                        pagina, numero_solicitacao, id_trabalho, selecao_confirmada=True
                    ):
                        continue

                    log("")
                    log("****************************************")
                    log("TRABALHO ABERTO COM SUCESSO")
                    log("****************************************")
                    log(
                        "SOLICITAÇÃO/TRABALHO CONFIRMADO: "
                        f"{numero_solicitacao}/{id_trabalho}"
                    )
                    log(f"URL: {url_atual}")
                    log("")
                    return pagina
            except Exception:
                continue

        try:
            if eh_trabalho(page.url) and validar_tela_trabalho(
                page, numero_solicitacao, id_trabalho, selecao_confirmada=True
            ):
                return page
        except Exception:
            pass

        # Keep Playwright's event dispatch alive: a normal Python sleep can
        # leave a delayed link/popup navigation invisible until this loop ends.
        page.wait_for_timeout(200)

    log("Tempo limite aguardando Trabalho.aspx.")
    log(f"URL atual: {page.url}")
    return None

def validar_tela_trabalho(pagina, numero_solicitacao, id_trabalho, *, selecao_confirmada=False):
    """
    Confirma que Trabalho.aspx corresponde exatamente à chave
    Solicitação/Trabalho recebida do Flutter (ex.: 2265173/4).
    """
    numero_solicitacao = str(numero_solicitacao or "").strip()
    id_trabalho = str(id_trabalho or "").strip()
    referencia_esperada = f"{numero_solicitacao}/{id_trabalho}"

    if pagina is None:
        return False

    try:
        if pagina.is_closed() or not eh_trabalho(pagina.url):
            return False
    except Exception:
        return False

    # Valida pelos parâmetros da URL, quando o E-Desk os fornece.
    try:
        dados_url = extrair_dados_url_trabalho(pagina.url)
        solicitacao_url = str(dados_url.get("solicitacao", "") or "").strip()
        trabalho_url = str(dados_url.get("id_trabalho", "") or "").strip()

        if (
            solicitacao_url
            and trabalho_url
            and solicitacao_url == numero_solicitacao
            and trabalho_url == id_trabalho
        ):
            log(f"Trabalho.aspx validado pela URL: {referencia_esperada}")
            return True
    except Exception:
        pass

    # Confirma pela informação visual "Solicitação/Trabalho 2265173/4".
    try:
        corpo = pagina.locator("body").inner_text(timeout=5000)
        corpo_compacto = re.sub(r"\s+", " ", corpo or "")
        padrao = re.compile(
            rf"Solicita[cç][aã]o\s*/\s*Trabalho\s*:?\s*"
            rf"{re.escape(numero_solicitacao)}\s*/\s*{re.escape(id_trabalho)}(?!\d)",
            re.IGNORECASE,
        )

        if padrao.search(corpo_compacto):
            log(f"Trabalho.aspx validado pelo texto da tela: {referencia_esperada}")
            return True

        # The original selected row may identify the stage by Ordem, while the
        # opened work displays another human-readable work reference. Accept
        # this mapping only following that exact row selection, in a fresh page
        # from the click, with matching request and a unique labeled Ordem.
        shown = re.search(r'Solicita[cç][aã]o\s*/\s*Trabalho\s*:?\s*(\d+)\s*/\s*(\d+)(?!\d)',
                          corpo_compacto, re.IGNORECASE)
        previous = getattr(pagina, '_edesk_validated_selection', None)
        actual_id = str(extrair_dados_url_trabalho(pagina.url).get('id_trabalho', '') or '')
        identity = (numero_solicitacao, id_trabalho, shown[2] if shown else '', actual_id)
        if shown and actual_id and shown[1] == numero_solicitacao and (selecao_confirmada or previous == identity):
            orders = pagina.evaluate(r'''() => {
              const norm = s => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase();
              const visible = e => !!(e && e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden');
              const values=[];
              for(const label of document.querySelectorAll('label,td,span')) {
                if(!visible(label) || norm(label.textContent)!=='ordem')continue;
                const control=label.control;
                if(control && visible(control)) { values.push(control.value.trim()); continue; }
                const scope=label.closest('tr');
                if(!scope)continue;
                const inputs=[...scope.querySelectorAll('input:not([type="hidden"]):not([type="button"]):not([type="submit"]),select')].filter(visible);
                if(inputs.length===1)values.push(inputs[0].value.trim());
              }
              return [...new Set(values)];
            }''')
            if orders == [id_trabalho]:
                pagina._edesk_validated_selection = identity
                log(f'Trabalho validado pela linha selecionada e Ordem {id_trabalho}; referencia exibida {shown[1]}/{shown[2]}.')
                return True
    except Exception as erro:
        log(f"Aviso ao validar Solicitação/Trabalho na tela: {erro}")

    log(
        "Trabalho.aspx rejeitado: a tela não confirmou "
        f"Solicitação/Trabalho {referencia_esperada}."
    )
    return False


def abrir_trabalho_retroativo(pagina_trabalho, dados_trabalho):
    log("")
    log("============================================================")
    log("ABRINDO TELA TRABALHO RETROATIVO")
    log("============================================================")

    if pagina_trabalho is None:
        return None

    dados_url = extrair_dados_url(pagina_trabalho.url)
    guid = str((dados_trabalho.get("guid", "") or dados_url.get("guid", "") or obter_guid_da_url(pagina_trabalho.url)) or "").strip()
    solicitacao = str((dados_trabalho.get("solicitacao", "") or dados_url.get("solicitacao", "")) or "").strip()
    id_trabalho = str((dados_trabalho.get("id_trabalho", "") or dados_url.get("id_trabalho", "")) or "").strip()

    log(f"GUID: {guid}")
    log(f"SOLICITAÇÃO: {solicitacao}")
    log(f"ID TRABALHO E-DESK: {id_trabalho}")

    if not guid:
        raise RuntimeError('Não foi possível abrir o retroativo: sessão do trabalho não identificada.')

    if not id_trabalho:
        raise RuntimeError('Não foi possível abrir o retroativo: identificador do trabalho ausente.')

    parametros = {
        "GUID": guid,
        "id_trabalho": id_trabalho,
    }

    if solicitacao:
        parametros["solicitacao"] = solicitacao

    url_retroativo = "https://promob.e-desk.com.br/Portal/TrabalhoRetroativo.aspx?" + urlencode(parametros)
    log(f"Acessando TrabalhoRetroativo: {url_retroativo}")

    try:
        pagina_trabalho.goto(url_retroativo, wait_until="domcontentloaded", timeout=30000)
        if eh_trabalho_retroativo(pagina_trabalho.url):
            pagina_trabalho.locator('#cph1_txtDatTem').wait_for(state='visible', timeout=20000)
            log("")
            log("****************************************")
            log("TELA TRABALHO RETROATIVO ABERTA COM SUCESSO")
            log("****************************************")
            log(f"URL: {pagina_trabalho.url}")
            log("")
            return pagina_trabalho
    except Exception as erro:
        log(f"Erro ao abrir TrabalhoRetroativo: {erro}")

    raise RuntimeError('Não foi possível abrir o formulário de horas retroativas. Confira a sessão e as permissões no E-Desk.')

def salvar_mapeamento(dados):
    arquivo = LOGS_PATH / "mapeamento_trabalho_cmd.json"
    try:
        registros = []
        if arquivo.exists():
            try:
                with arquivo.open("r", encoding="utf-8") as f:
                    registros = json.load(f)
            except Exception:
                registros = []

        registros.append(dados)
        with arquivo.open("w", encoding="utf-8") as f:
            json.dump(registros, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def fechar_solicitacoes_duplicadas(context, selecionada, principal, snapshot):
    for candidata in list(context.pages):
        if candidata is selecionada or candidata is principal or id(candidata) in snapshot:
            continue
        try:
            if (not candidata.is_closed() and eh_solicitacao(candidata.url)
                    and candidata.url == selecionada.url):
                candidata.close()
        except Exception:
            pass


def abrir_trabalho(page, context, linha_grid, numero_solicitacao, id_trabalho, pagina_solicitacao_preaberta=None, abrir_retroativo=True, somente_solicitacao=False, validar_solicitacao=None):
    id_trabalho = str(id_trabalho).strip()
    numero_solicitacao = str(numero_solicitacao).strip()

    log("")
    log("============================================================")
    log("ABERTURA DA SOLICITAÇÃO E TRABALHO")
    log(f"SOLICITAÇÃO: {numero_solicitacao}")
    log(f"TRABALHO RELATIVO: {id_trabalho}")
    log("============================================================")

    guid = obter_guid_da_url(page.url)
    if not guid:
        raise RuntimeError("GUID da sessão não encontrado antes de abrir solicitação.")

    if linha_grid is None and pagina_solicitacao_preaberta is None:
        raise RuntimeError(
            f"A linha da solicitação {numero_solicitacao} não foi encontrada "
            "e nenhuma Solicitação.aspx foi aberta pela pesquisa."
        )

    # Snapshot completo. A partir daqui só aceitamos uma Solicitação que seja
    # criada ou navegada pela ação DESTE ciclo. Nunca reutilizamos uma aba
    # Solicitação.aspx antiga deixada por uma hora/trabalho anterior.
    paginas_antes = {id(p): (p.url or "") for p in context.pages if not p.is_closed()}
    url_grid_antes = page.url or ""
    pagina_solicitacao = pagina_solicitacao_preaberta

    def contem_trabalho_esperado(pagina):
        if somente_solicitacao:
            if not eh_solicitacao(pagina.url):
                return False
            if validar_solicitacao is not None:
                validar_solicitacao(pagina)
                return True
            pagina.get_by_text(re.compile(r'^Coment\u00e1rios\s*(?:\(\d+\))?$')).wait_for(state='visible', timeout=20000)
            return True
        inicio = time.time()
        while time.time() - inicio < 15:
            try:
                tabela = pagina.locator(
                    "#cph1_rpvTrabalhos #cph1_gvwTra"
                ).first
                if tabela.count() and resolve_work_selection(tabela, id_trabalho) is not None:
                    return True
            except Exception:
                pass

            try:
                pagina.wait_for_timeout(250)
            except Exception:
                return False

        return False

    def capturar_solicitacao_deste_ciclo(timeout_segundos):
        inicio = time.time()
        paginas_em_branco_observadas = set()
        while time.time() - inicio < timeout_segundos:
            for pagina in list(context.pages):
                try:
                    if pagina.is_closed():
                        continue
                    url_atual = pagina.url or ""
                    pagina_nova = id(pagina) not in paginas_antes
                    pagina_grid_navegou = (
                        pagina is page
                        and url_atual != url_grid_antes
                    )
                    outra_pagina_navegou = (
                        id(pagina) in paginas_antes
                        and paginas_antes[id(pagina)] != url_atual
                    )

                    if not (pagina_nova or pagina_grid_navegou or outra_pagina_navegou):
                        continue

                    if pagina_nova and url_atual in ("", "about:blank"):
                        if id(pagina) not in paginas_em_branco_observadas:
                            log(
                                "Nova aba detectada após a ação; aguardando "
                                "sua navegação antes de decidir se a "
                                "Solicitação abriu."
                            )
                            paginas_em_branco_observadas.add(id(pagina))
                        continue

                    if not eh_solicitacao(url_atual):
                        continue

                    return pagina
                except Exception:
                    continue
            try:
                page.wait_for_timeout(250)
            except Exception:
                time.sleep(0.25)
        return None

    if pagina_solicitacao is not None:
        if contem_trabalho_esperado(pagina_solicitacao):
            log(
                "Solicitação aberta automaticamente pela pesquisa confirmada. "
                "Reutilizando sem novo clique na Grid."
            )
        else:
            log(
                "Solicitação aberta automaticamente foi rejeitada porque "
                f"não contém o trabalho {id_trabalho}."
            )
            raise RuntimeError(
                "A pesquisa já abriu uma tela de Solicitação, mas ela não "
                f"confirmou o trabalho {id_trabalho}. Para evitar abrir a "
                "solicitação em duplicidade, nenhum novo clique será feito."
            )

    # Dispara somente o evento de abertura da linha Telerik. dblclick()
    # também envia dois eventos click, que podem abrir duas solicitações.
    if pagina_solicitacao is None and linha_grid is not None:
        log(
            "Abrindo a solicitação com um único evento dblclick na linha "
            "selecionada..."
        )
        try:
            linha_grid.scroll_into_view_if_needed(timeout=5000)
            try:
                linha_grid.dispatch_event(
                    "dblclick", {"bubbles": True, "button": 0, "detail": 2},
                    timeout=10000,
                )
            except Exception as erro_clique:
                log(
                    "O duplo clique retornou erro; verificando se o E-Desk abriu "
                    f"a solicitação antes de decidir falha: {erro_clique}"
                )

            pagina_solicitacao = capturar_solicitacao_deste_ciclo(20)

            if pagina_solicitacao is None:
                raise RuntimeError(
                    "O duplo clique na linha não abriu uma tela válida de "
                    "Solicitação. O bot não repetirá a ação automaticamente."
                )

            # O grid pode deixar uma Solicitação.aspx duplicada aberta se
            # houver páginas antigas no contexto. Fecha somente cópias novas
            # desta mesma URL, preservando a página escolhida.
            pagina_solicitacao.wait_for_timeout(750)
            url_solicitacao_selecionada = pagina_solicitacao.url
            for pagina in list(context.pages):
                if pagina is pagina_solicitacao:
                    continue
                try:
                    if (
                        not pagina.is_closed()
                        and id(pagina) not in paginas_antes
                        and eh_solicitacao(pagina.url)
                        and pagina.url == url_solicitacao_selecionada
                    ):
                        pagina.close()
                        log(
                            "Aba duplicada da Solicitação aberta neste ciclo "
                            "foi fechada."
                        )
                except Exception as erro_fechamento:
                    log(
                        "Não foi possível fechar uma aba duplicada da "
                        f"Solicitação: {erro_fechamento}"
                    )

            if not contem_trabalho_esperado(pagina_solicitacao):
                raise RuntimeError(
                    "A tela da Solicitação foi aberta, mas não confirmou o "
                    f"trabalho {id_trabalho}. O bot não repetirá o duplo clique."
                )
        except Exception as erro:
            if isinstance(erro, RuntimeError):
                raise
            log(f"Falha ao tentar células da linha escolhida: {erro}")

    if pagina_solicitacao is None:
        log("")
        log("============================================================")
        log("FALHA AO ABRIR SOLICITAÇÃO")
        log("============================================================")
        log(f"SOLICITAÇÃO: {numero_solicitacao}")
        log(f"TRABALHO RELATIVO: {id_trabalho}")
        log(f"URL DA GRID NO INÍCIO: {url_grid_antes}")
        log(f"URL ATUAL DA PÁGINA DA GRID: {page.url if not page.is_closed() else '[FECHADA]'}")
        raise RuntimeError(
            "O E-Desk não abriu uma Solicitação.aspx válida contendo "
            f"o trabalho {id_trabalho}."
        )

    # Also remove duplicates created by the search itself, before selecting work.
    snapshot = getattr(pagina_solicitacao_preaberta, "_edesk_search_snapshot", paginas_antes)
    fechar_solicitacoes_duplicadas(context, pagina_solicitacao, page, snapshot)

    if somente_solicitacao:
        pagina_solicitacao.bring_to_front()
        return pagina_solicitacao

    pagina_solicitacao_atual = pagina_solicitacao
    log(f"Solicitação correta aberta: {pagina_solicitacao_atual.url}")

    dados_solicitacao = extrair_dados_url(pagina_solicitacao_atual.url)
    solicitacao_encoded = dados_solicitacao.get("solicitacao", "") or numero_solicitacao
    cmd = dados_solicitacao.get("cmd", "")
    url_solicitacao_mapeamento = pagina_solicitacao_atual.url

    pagina_trabalho = abrir_trabalho_na_solicitacao(
        pagina_solicitacao_atual,
        context,
        numero_solicitacao,
        id_trabalho,
    )
    if not pagina_trabalho:
        log("Não foi possível abrir Trabalho.aspx.")
        raise RuntimeError(
            f"Não foi possível abrir o trabalho relativo {id_trabalho} "
            f"da solicitação {numero_solicitacao}."
        )

    # Fecha somente a Solicitação intermediária criada em uma NOVA página.
    # Se a Grid original navegou para Solicitação, não a fechamos: ela é a
    # página principal que o loop reutilizará para voltar à Grid.
    if pagina_trabalho is not pagina_solicitacao_atual:
        try:
            solicitacao_era_pagina_nova = id(pagina_solicitacao_atual) not in paginas_antes
            if solicitacao_era_pagina_nova and not pagina_solicitacao_atual.is_closed():
                pagina_solicitacao_atual.close()
                log("Aba intermediária criada para a Solicitação foi fechada.")
        except Exception as erro:
            log(f"Aviso ao fechar aba intermediária da Solicitação: {erro}")

    dados_trabalho = extrair_dados_url(pagina_trabalho.url)
    id_efetivo = dados_trabalho.get("id_trabalho", "") or id_trabalho

    if not dados_trabalho.get("guid"):
        dados_trabalho["guid"] = guid
    if not dados_trabalho.get("solicitacao"):
        dados_trabalho["solicitacao"] = solicitacao_encoded
    if not dados_trabalho.get("id_trabalho"):
        dados_trabalho["id_trabalho"] = id_efetivo

    mapeamento = {
        "solicitacao": numero_solicitacao,
        "idTrabalhoFlutter": id_trabalho,
        "idTrabalhoEdesk": id_efetivo,
        "cmd": cmd,
        "solicitacaoEncoded": solicitacao_encoded,
        "guid": guid,
        "urlSolicitacao": url_solicitacao_mapeamento,
        "urlTrabalho": pagina_trabalho.url,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }

    salvar_mapeamento(mapeamento)
    log("")
    log("MAPEAMENTO DO TRABALHO")
    log(json.dumps(mapeamento, ensure_ascii=False, indent=2))
    log("")

    if not abrir_retroativo:
        return pagina_trabalho
    pagina_horas = abrir_trabalho_retroativo(pagina_trabalho, dados_trabalho)
    pagina_horas._edesk_hours_reference = {
        'urlSolicitacao': url_solicitacao_mapeamento,
        'dadosTrabalho': dict(dados_trabalho),
    }
    return pagina_horas


def preparar_tela_hora(page, context, numero_solicitacao, id_trabalho, referencia):
    """Re-enter the validated work after Save redirects/closes the hours page.

    Only navigation is retried here, never Save. A previous hour's journal
    events stay intact and the next hour has not been submitted yet.
    """
    dados_esperados = referencia.get('dadosTrabalho', {})
    url_solicitacao = referencia.get('urlSolicitacao', '')
    if not dados_esperados.get('id_trabalho') or not eh_solicitacao(url_solicitacao):
        raise RuntimeError('Não foi possível recuperar a referência validada do trabalho para a próxima hora.')

    if page is not None and not page.is_closed():
        # Deliver pending Playwright navigation events after the previous POST.
        page.wait_for_timeout(100)
        if eh_trabalho_retroativo(page.url):
            atuais = extrair_dados_url(page.url)
            corresponde = all(str(atuais.get(key, '')) == str(dados_esperados.get(key, ''))
                              for key in ('solicitacao', 'id_trabalho'))
            if corresponde and page.locator('#cph1_txtDatTem').is_visible():
                return page
    else:
        page = context.new_page()

    log('O E-Desk saiu do formulário de horas. Reabrindo o trabalho validado antes do próximo apontamento.')
    atuais = extrair_dados_url(page.url)
    mesmo_trabalho = all(str(atuais.get(key, '')) == str(dados_esperados.get(key, ''))
                        for key in ('solicitacao', 'id_trabalho'))
    if not (eh_trabalho(page.url) and mesmo_trabalho and validar_tela_trabalho(page, numero_solicitacao, id_trabalho)):
        atuais = extrair_dados_url(page.url)
        mesma_solicitacao = (eh_solicitacao(page.url) and
                            str(atuais.get('solicitacao', '')) == str(dados_esperados.get('solicitacao', '')))
        if not mesma_solicitacao:
            try:
                page.goto(url_solicitacao, wait_until='domcontentloaded', timeout=30000)
            except Exception as erro:
                raise RuntimeError('Não foi possível reabrir a solicitação. Confira a sessão e a conexão antes de enviar as horas restantes.') from erro
        if not eh_solicitacao(page.url):
            raise RuntimeError('O E-Desk não reabriu a solicitação. Confira a sessão antes de enviar as horas restantes.')
        page = abrir_trabalho_na_solicitacao(page, context, numero_solicitacao, id_trabalho)

    if page is None or not validar_tela_trabalho(page, numero_solicitacao, id_trabalho):
        raise RuntimeError('O trabalho da próxima hora não foi confirmado. Nenhum novo apontamento foi enviado.')
    dados_trabalho = extrair_dados_url(page.url)
    if any(str(dados_trabalho.get(key, '')) != str(dados_esperados.get(key, ''))
           for key in ('solicitacao', 'id_trabalho')):
        raise RuntimeError('A referência do trabalho mudou entre as horas. Nenhum novo apontamento foi enviado.')
    pagina_horas = abrir_trabalho_retroativo(page, dados_trabalho)
    referencia['dadosTrabalho'] = dict(dados_trabalho)
    pagina_horas._edesk_hours_reference = referencia
    return pagina_horas


def acrescentar_trabalho_realizado(anterior, atual, data, descritivo, retry=False):
    # Não sobrescreve uma alteração inesperada durante o postback.
    if anterior and atual and not atual.startswith(anterior):
        raise RuntimeError(
            "O comentário existente mudou durante o preenchimento. "
            "Envio interrompido para preservar o trabalho realizado."
        )
    existente = atual or anterior
    addition = f"{data}: - {descritivo}"
    if retry and ('\n' + addition + '\n') in ('\n' + existente.replace('\r\n', '\n') + '\n'):
        return existente
    separador = "" if not existente or existente.endswith(("\n", "\r")) else "\n"
    return existente + separador + addition


def salvar_hora(page, hora, indice_hora, total_horas):
    """
    Salva uma hora no E-Desk usando o POST AJAX do ASP.NET WebForms.

    O login e toda a navegação continuam usando a sessão autenticada
    do Playwright.

    Somente o salvamento deixa de depender do clique visual no botão
    Salvar. O POST é executado dentro da própria página, preservando:
    - cookies da sessão;
    - VIEWSTATE;
    - EVENTVALIDATION;
    - campos ocultos;
    - estado atual do formulário WebForms.
    """

    log("")
    log("============================================================")
    log(f"SALVANDO HORA {indice_hora} DE {total_horas} VIA HTTP")
    log("============================================================")

    # ============================================================
    # 1. VALIDA OS DADOS RECEBIDOS
    # ============================================================

    if not isinstance(hora, dict):
        raise RuntimeError(
            f"A HORA {indice_hora} não é um objeto JSON válido."
        )

    data = obter_data_hora(hora)
    inicio = obter_inicio_hora(hora)
    fim = obter_fim_hora(hora)

    descritivo_original = obter_descritivo_hora(hora)

    descritivo = limpar_descritivo_hora(
        descritivo_original,
        data,
    )

    log("")
    log(f"DADOS DA HORA {indice_hora}")
    log(f"Data: {data}")
    log(f"Início: {inicio}")
    log(f"Fim: {fim}")

    log(
        f"Descritivo recebido: "
        f"{descritivo_original or '[NÃO INFORMADO]'}"
    )

    log(
        f"Descritivo limpo: "
        f"{descritivo or '[NÃO INFORMADO]'}"
    )

    log("")

    if not data:
        raise RuntimeError(
            f"A HORA {indice_hora} não possui data."
        )

    if not inicio:
        raise RuntimeError(
            f"A HORA {indice_hora} não possui horário de início."
        )

    if not fim:
        raise RuntimeError(
            f"A HORA {indice_hora} não possui horário de fim."
        )

    if not descritivo:
        raise RuntimeError(
            f"A HORA {indice_hora} não possui descritivo."
        )

    tipo = str(hora.get("tipo", "0") or "0").strip()
    tipos_por_nome = {
        "interno": "0",
        "externo": "1",
        "padrão": "3",
        "padrao": "3",
        "padrão (interno)": "4",
        "padrao (interno)": "4",
    }
    tipo = tipos_por_nome.get(tipo.lower(), tipo)

    if not tipo:
        tipo = "0"

    # ============================================================
    # 2. CONFIRMA QUE ESTAMOS NA TELA CORRETA
    # ============================================================

    if not eh_trabalho_retroativo(page.url):
        raise RuntimeError(
            "A página atual não é TrabalhoRetroativo.aspx. "
            f"URL atual: {page.url}"
        )

    log(f"Tela de horas confirmada: {page.url}")

    # ============================================================
    # 3. LOCALIZA OS CAMPOS
    # ============================================================

    campo_data = page.locator("#cph1_txtDatTem")
    campo_inicio = page.locator("#cph1_txtHorIni")
    campo_fim = page.locator("#cph1_txtHorFin")
    campo_tipo = page.locator("#cph1_ddlTipReg")
    campo_rea = page.locator("#cph1_txtRea")

    campos = [
        ("Data", campo_data),
        ("Início", campo_inicio),
        ("Fim", campo_fim),
        ("Tipo", campo_tipo),
        ("Descritivo", campo_rea),
    ]

    for nome, elemento in campos:

        try:

            elemento.wait_for(
                state="visible",
                timeout=15000,
            )

        except Exception as erro:

            raise RuntimeError(
                f"Campo '{nome}' não ficou disponível: {erro}"
            )

    # ============================================================
    # 4. PREENCHE A TELA
    #
    # Mantemos o preenchimento normal porque o E-Desk pode utilizar
    # JavaScript/postback para atualizar estado interno do formulário.
    # ============================================================

    log("")
    log("PREENCHENDO CAMPOS DA HORA...")

    # Guarda o histórico antes de qualquer postback do formulário.
    trabalho_realizado_anterior = campo_rea.input_value()

    log(f"Preenchendo DATA: {data}")

    campo_data.fill(data)

    log(f"Preenchendo INÍCIO: {inicio}")

    campo_inicio.fill(inicio)

    log(f"Preenchendo FIM: {fim}")

    campo_fim.fill(fim)

    # ============================================================
    # 5. TIPO DE REGISTRO
    # ============================================================

    log(f"Selecionando TIPO DE REGISTRO: {tipo}")

    try:

        campo_tipo.select_option(tipo)

    except Exception as erro:

        raise RuntimeError(
            f"Erro ao selecionar tipo de registro '{tipo}': {erro}"
        )

    # Pequena espera apenas para permitir que eventual AJAX/postback
    # da seleção termine.
    page.wait_for_timeout(500)

    # ============================================================
    # 6. RECUPERA OS CAMPOS NOVAMENTE
    #
    # ASP.NET UpdatePanel pode substituir elementos do DOM.
    # ============================================================

    campo_data = page.locator("#cph1_txtDatTem")
    campo_inicio = page.locator("#cph1_txtHorIni")
    campo_fim = page.locator("#cph1_txtHorFin")
    campo_tipo = page.locator("#cph1_ddlTipReg")
    campo_rea = page.locator("#cph1_txtRea")

    # Reaplica os valores caso o postback da seleção tenha alterado
    # algum deles.

    campo_data.fill(data)
    campo_inicio.fill(inicio)
    campo_fim.fill(fim)

    # Relê o histórico após o postback e preserva também o conteúdo inicial
    # caso o E-Desk tenha limpado o campo durante a atualização do formulário.
    texto_existente = campo_rea.input_value() or trabalho_realizado_anterior
    trabalho_realizado = acrescentar_trabalho_realizado(
        trabalho_realizado_anterior, texto_existente, data, descritivo,
        retry=hora.get('_receiptRetry') is True
    )
    log("")
    log("CONTEÚDO DO txtRea PARA ESTE LANÇAMENTO:")
    log(trabalho_realizado)

    campo_rea.fill(trabalho_realizado)

    # ============================================================
    # 8. CONFERÊNCIA
    # ============================================================

    log("")
    log("============================================================")
    log("CONFERÊNCIA ANTES DE SALVAR")
    log("============================================================")

    valores_esperados = {
        "Data": (campo_data, data),
        "Início": (campo_inicio, inicio),
        "Fim": (campo_fim, fim),
        "Tipo": (campo_tipo, tipo),
        "Descritivo": (campo_rea, trabalho_realizado),
    }

    for nome, (elemento, esperado) in valores_esperados.items():
        valor_atual = elemento.input_value()
        if nome != "Descritivo":
            valor_atual = valor_atual.strip()
        log(f"{nome}: {valor_atual}")
        if valor_atual != esperado:
            raise RuntimeError(
                f"Conferência da HORA {indice_hora} falhou antes do envio: "
                f"campo '{nome}' ficou com valor diferente do solicitado."
            )

    # ============================================================
    # 9. SALVAMENTO PELA INTERFACE ORIGINAL DO E-DESK
    # Trata exclusivamente a confirmação de apontamento > 4 horas.
    # ============================================================
    hour_event(hora, "started")
    hora['_saveOutcome'] = 'unknown'
    log("Clicando no botão Salvar do E-Desk...")
    requisicoes_salvar = set()
    posts_observados = set()
    requisicoes_concluidas = set()
    respostas_salvar = []
    confirmacoes = []
    event_source = page.context

    def registrar_requisicao(requisicao):
        try:
            if requisicao.method != 'POST':
                return
            key = (requisicao.url, requisicao.post_data or '')
            try:
                sender = requisicao.frame.page
            except Exception:
                posts_observados.add(key)  # Cannot safely rule out a submitted request.
                return
            if sender is not page:
                return
            posts_observados.add(key)
            if 'TrabalhoRetroativo.aspx' not in requisicao.url:
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
                or "HiddenButton" in chave
                or chave == "CustomPostBack"
            ]
            if any(
                identificador in alvo
                for alvo in targets
                for identificador in ("BtAtu", "HiddenButton", "CustomPostBack")
            ) or controles:
                requisicoes_salvar.add(
                    (requisicao.url, requisicao.post_data or "")
                )
                log(
                    "POST do comando Salvar/Confirmação detectado "
                    f"(controles={controles or targets})."
                )
        except Exception as erro:
            log(f"Não foi possível classificar POST do salvamento: {erro}")

    def registrar_resposta(resposta):
        try:
            chave_requisicao = (
                resposta.request.url,
                resposta.request.post_data or "",
            )
            if chave_requisicao in requisicoes_salvar:
                respostas_salvar.append(resposta)
        except Exception:
            log("Não foi possível associar a resposta ao POST de salvamento.")

    def registrar_conclusao(requisicao):
        key = (requisicao.url, requisicao.post_data or '')
        if key in requisicoes_salvar:
            requisicoes_concluidas.add(key)

    def post_completed():
        return (bool(requisicoes_salvar) and requisicoes_salvar <= requisicoes_concluidas
                and bool(respostas_salvar) and all(response.ok for response in respostas_salvar))

    def post_finished():
        return bool(requisicoes_salvar) and requisicoes_salvar <= requisicoes_concluidas and bool(respostas_salvar)

    def pump(milliseconds):
        for candidate in [page, *event_source.pages]:
            try:
                if not candidate.is_closed():
                    candidate.wait_for_timeout(milliseconds)
                    return
            except Exception:
                continue
        raise RuntimeError('O navegador fechou antes da conferência das horas.')

    def tratar_dialogo(dialogo):
        mensagem = dialogo.message or ""
        log(f"Diálogo do navegador: {mensagem}")
        if "4 horas" in mensagem.lower() and "apontamento" in mensagem.lower():
            confirmacoes.append("nativo")
            dialogo.accept()
        else:
            dialogo.dismiss()
            raise RuntimeError(f"Confirmação inesperada do E-Desk: {mensagem}")

    event_source.on("request", registrar_requisicao)
    event_source.on("response", registrar_resposta)
    event_source.on('requestfinished', registrar_conclusao)
    page.on("dialog", tratar_dialogo)
    try:
        botao = page.locator("#cph1_BtAtu").first
        botao.wait_for(state="visible", timeout=15000)
        botao.click(timeout=15000)

        # O E-Desk pode apresentar uma confirmação Telerik em HTML.
        # Só confirmamos se o texto indicar explicitamente > 4 horas.
        for tentativa in range(60):
            pump(300)
            confirmou = False
            if "telerik" not in confirmacoes and not page.is_closed():
                confirmou = page.evaluate("""() => {
                const visivel = e => {
                    const s = getComputedStyle(e);
                    return s.display !== 'none' && s.visibility !== 'hidden'
                        && e.getBoundingClientRect().width > 0;
                };
                const caixas = [...document.querySelectorAll(
                    '.rwWindow, .radalert, .radconfirm, [role="dialog"], .TelerikModalOverlay'
                )].filter(visivel);
                const caixa = caixas.find(e => /apontamento de tempo maior que 4 horas/i.test(e.innerText || ''));
                if (!caixa) return false;
                const botoes = [...document.querySelectorAll('button, input[type="button"], a')]
                    .filter(visivel);
                const sim = botoes.find(e => {
                    const t = (e.innerText || e.value || e.title || '').trim();
                    return /^sim$/i.test(t) && (caixa.contains(e) ||
                        (e.closest('.rwWindow, [role="dialog"]') === caixa));
                });
                if (!sim) return false;
                sim.click();
                return true;
            }""")
            if confirmou:
                confirmacoes.append("telerik")
                log("Confirmação de mais de 4 horas: SIM.")
                continue
            if respostas_salvar:
                break

        inicio_espera_resposta = time.time()
        while not post_finished() and time.time() - inicio_espera_resposta < 20:
            pump(250)

        if not respostas_salvar:
            raise RuntimeError(
                f"Nenhuma resposta ao POST do comando Salvar foi observada "
                f"para a HORA {indice_hora}. O bot não repetirá o envio para "
                "evitar cadastrar a mesma hora duas vezes."
            )
        resposta = respostas_salvar[-1]
        if not resposta.ok:
            raise RuntimeError(
                f"E-Desk retornou HTTP {resposta.status} ao salvar a HORA {indice_hora}."
            )
        if not post_completed():
            raise RuntimeError('O POST não terminou de forma comprovada. A conferência não repetirá este envio sem segurança.')
        # Reading a response body after E-Desk detaches/closes its frame can
        # stall Playwright. Persisted rows, not response HTML, confirm success.
        log(f"POST do E-Desk concluído: HTTP {resposta.status}.")
        if confirmacoes:
            log("Confirmação de mais de 4 horas tratada.")
        log("ATENÇÃO: HTTP 200 não comprova, sozinho, persistência da hora.")
        hora['_saveOutcome'] = 'completed'
    except Exception:
        if not posts_observados:
            hora['_saveOutcome'] = 'not_submitted'
            hour_event(hora, 'not_submitted')
        elif post_completed():
            hora['_saveOutcome'] = 'completed'
        raise
    finally:
        event_source.remove_listener("request", registrar_requisicao)
        event_source.remove_listener("response", registrar_resposta)
        event_source.remove_listener('requestfinished', registrar_conclusao)
        page.remove_listener("dialog", tratar_dialogo)

    # Confirmation is emitted only by the independent, fresh grid read.
    log(f"HORA {indice_hora}: operação de salvamento concluída na interface.")

    return True

def diagnosticar_tela_horas(page):
    log("")
    log("============================================================")
    log("DIAGNÓSTICO COMPLETO DA TELA DE HORAS")
    log("============================================================")
    log(f"URL atual: {page.url}")

    campos_procurados = [
        "txtDatTem", "txtHorIni", "txtHorFin", "ddlTipReg",
        "txlGtt", "txlTtr", "txlEqt", "txlAte", "txtDet", "txtRea",
    ]

    try:
        frames = page.frames
        log("")
        log(f"TOTAL DE FRAMES ENCONTRADOS: {len(frames)}")
    except Exception as erro:
        log(f"Erro ao obter frames: {erro}")
        frames = []

    for indice_frame, frame in enumerate(frames):
        log("")
        log("------------------------------------------------------------")
        log(f"FRAME {indice_frame}")
        log("------------------------------------------------------------")

        try:
            log(f"URL DO FRAME: {frame.url}")
        except Exception:
            log("URL DO FRAME: não disponível")

        for nome_campo in campos_procurados:
            try:
                elementos = frame.locator(f'[id*="{nome_campo}"], [name*="{nome_campo}"]')
                quantidade = elementos.count()
                if quantidade > 0:
                    log("")
                    log(f"*** CAMPO PROCURADO: {nome_campo} -> {quantidade} encontrado(s)")
                    for indice in range(quantidade):
                        elemento = elementos.nth(indice)
                        try:
                            tag = elemento.evaluate("(el) => el.tagName")
                        except Exception:
                            tag = ""
                        try:
                            id_elemento = elemento.get_attribute("id") or ""
                        except Exception:
                            id_elemento = ""
                        try:
                            name_elemento = elemento.get_attribute("name") or ""
                        except Exception:
                            name_elemento = ""
                        try:
                            tipo_elemento = elemento.get_attribute("type") or ""
                        except Exception:
                            tipo_elemento = ""
                        try:
                            valor_elemento = elemento.get_attribute("value") or ""
                        except Exception:
                            valor_elemento = ""
                        try:
                            texto_elemento = elemento.inner_text(timeout=1000).strip()
                        except Exception:
                            texto_elemento = ""

                        log(f"  TAG: {tag}")
                        log(f"  ID: {id_elemento}")
                        log(f"  NAME: {name_elemento}")
                        log(f"  TYPE: {tipo_elemento}")
                        log(f"  VALUE: {valor_elemento}")
                        if texto_elemento:
                            log(f"  TEXTO: {texto_elemento[:300]}")
            except Exception as erro:
                log(f"Erro procurando {nome_campo}: {erro}")

        try:
            inputs = frame.locator("input")
            quantidade_inputs = inputs.count()
            log("")
            log(f"INPUTS ENCONTRADOS NO FRAME: {quantidade_inputs}")

            for indice in range(quantidade_inputs):
                elemento = inputs.nth(indice)
                try:
                    id_elemento = elemento.get_attribute("id") or ""
                    name_elemento = elemento.get_attribute("name") or ""
                    tipo_elemento = elemento.get_attribute("type") or ""
                    valor_elemento = elemento.get_attribute("value") or ""
                    placeholder = elemento.get_attribute("placeholder") or ""
                    onclick = elemento.get_attribute("onclick") or ""

                    descricao = f"INPUT {indice} | id={id_elemento} | name={name_elemento} | type={tipo_elemento} | value={valor_elemento} | placeholder={placeholder}"
                    texto_busca = (descricao + " " + onclick).lower()
                    relevante = any(campo.lower() in texto_busca for campo in campos_procurados)

                    if relevante:
                        log(f"  [RELEVANTE] {descricao}")
                        if onclick:
                            log(f"      onclick={onclick[:500]}")
                    else:
                        log(f"  {descricao}")
                except Exception as erro:
                    log(f"  INPUT {indice} -> erro: {erro}")
        except Exception as erro:
            log(f"Erro ao listar inputs: {erro}")

        try:
            selects = frame.locator("select")
            quantidade_selects = selects.count()
            log("")
            log(f"SELECTS ENCONTRADOS NO FRAME: {quantidade_selects}")

            for indice in range(quantidade_selects):
                elemento = selects.nth(indice)
                try:
                    id_elemento = elemento.get_attribute("id") or ""
                    name_elemento = elemento.get_attribute("name") or ""
                    valor_elemento = elemento.input_value()
                    texto = elemento.inner_text(timeout=1000).strip()

                    log(f"  SELECT {indice} | id={id_elemento} | name={name_elemento} | value={valor_elemento}")
                    if texto:
                        log(f"      opções/texto: {texto[:500]}")
                except Exception as erro:
                    log(f"  SELECT {indice} -> erro: {erro}")
        except Exception as erro:
            log(f"Erro ao listar selects: {erro}")

        try:
            textareas = frame.locator("textarea")
            quantidade_textareas = textareas.count()
            log("")
            log(f"TEXTAREAS ENCONTRADOS NO FRAME: {quantidade_textareas}")

            for indice in range(quantidade_textareas):
                elemento = textareas.nth(indice)
                try:
                    id_elemento = elemento.get_attribute("id") or ""
                    name_elemento = elemento.get_attribute("name") or ""
                    valor_elemento = elemento.input_value()

                    log(f"  TEXTAREA {indice} | id={id_elemento} | name={name_elemento} | value={valor_elemento[:500]}")
                except Exception as erro:
                    log(f"  TEXTAREA {indice} -> erro: {erro}")
        except Exception as erro:
            log(f"Erro ao listar textareas: {erro}")

        try:
            botoes = frame.locator("button, input[type='button'], input[type='submit']")
            quantidade_botoes = botoes.count()
            log("")
            log(f"BOTÕES ENCONTRADOS NO FRAME: {quantidade_botoes}")

            for indice in range(quantidade_botoes):
                elemento = botoes.nth(indice)
                try:
                    id_elemento = elemento.get_attribute("id") or ""
                    name_elemento = elemento.get_attribute("name") or ""
                    tipo_elemento = elemento.get_attribute("type") or ""
                    value_elemento = elemento.get_attribute("value") or ""
                    texto_elemento = elemento.inner_text(timeout=500).strip()
                    onclick = elemento.get_attribute("onclick") or ""

                    log(f"  BOTÃO {indice} | id={id_elemento} | name={name_elemento} | type={tipo_elemento} | value={value_elemento} | texto={texto_elemento[:150]}")
                    if onclick:
                        log(f"      onclick={onclick[:500]}")
                except Exception:
                    continue
        except Exception as erro:
            log(f"Erro ao listar botões: {erro}")

    log("")
    log("============================================================")
    log("FIM DO DIAGNÓSTICO DA TELA DE HORAS")
    log("============================================================")
    log("")

def aguardar_navegador(context):
    while True:
        try:
            paginas = [pagina for pagina in context.pages if not pagina.is_closed()]
            if not paginas:
                break
            time.sleep(0.5)
        except Exception:
            break

def fechar_playwright(context, playwright):
    log("")
    log("============================================================")
    log("ENCERRANDO AUTOMAÇÃO E-DESK")
    log("============================================================")

    if context is not None:
        try:
            paginas = list(context.pages)
            log(f"Páginas abertas antes do encerramento: {len(paginas)}")
        except Exception:
            paginas = []

        try:
            save_session_cookies(context)
            context.close()
            log("Contexto Playwright encerrado.")
        except Exception as erro:
            log(f"Aviso ao fechar contexto Playwright: {erro}")

    if playwright is not None:
        try:
            playwright.stop()
            log("Playwright encerrado.")
        except Exception as erro:
            log(f"Aviso ao parar Playwright: {erro}")

    log("Automação E-Desk finalizada.")
    log("")

def main():
    dados = carregar_request()
    credenciais = obter_credenciais_edesk(dados)
    url = obter_url(dados)
    trabalhos = extrair_trabalhos(dados)
    enviar = obter_modo_envio(dados)
    manter_navegador_aberto = obter_manter_navegador_aberto(dados)

    if not trabalhos:
        raise RuntimeError("Nenhum trabalho foi informado no request.")

    log("")
    log("============================================================")
    log("RESUMO DOS DADOS DO REQUEST")
    log("============================================================")
    log(f"URL: {url}")
    log(f"Quantidade de trabalhos: {len(trabalhos)}")

    for indice, trabalho in enumerate(trabalhos, start=1):
        solicitacao = trabalho.get("solicitacao", "")
        id_trabalho = trabalho.get("id_trabalho", "")
        horas = trabalho.get("horas", [])

        log(
            f"TRABALHO {indice}: "
            f"Solicitação={solicitacao} | "
            f"Trabalho={id_trabalho} | "
            f"Horas={len(horas)}"
        )

    log(f"Modo envio: {enviar}")
    log(f"Manter navegador aberto: {manter_navegador_aberto}")
    log(f"Arquivo de log desta execução: {RUN_LOG_PATH}")
    log("============================================================")
    log("")

    if enviar:
        manter_navegador_aberto = False

    playwright = None
    context = None
    page = None
    pagina_hora_em_processamento = None
    indice_hora_em_processamento = None

    try:
        playwright = sync_playwright().start()

        context = playwright.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_PATH),
            headless=False,
            args=["--start-maximized"],
            viewport=None,
        )

        restore_session_cookies(context)
        instalar_monitor_navegacao(context)

        page = None

        # ============================================================
        # LOCALIZA UMA PÁGINA EXISTENTE DO E-DESK
        # ============================================================

        for pagina_existente in context.pages:
            try:
                if pagina_existente.is_closed():
                    continue

                url_existente = pagina_existente.url or ""

                if (
                    "/Portal/" in url_existente
                    or "promob.e-desk.com.br" in url_existente
                ):
                    page = pagina_existente
                    break

            except Exception:
                continue

        if page is None:
            if context.pages:
                page = context.pages[0]
            else:
                page = context.new_page()

        instalar_monitor_requests(page)

        # ============================================================
        # LOGIN
        # ============================================================

        autenticado = login_confirmado(page)

        if not autenticado:
            log("")
            log("============================================================")
            log("ABRINDO E-DESK - PRIMEIRA VEZ NESTA SESSÃO")
            log("============================================================")

            page.goto(
                url,
                wait_until="domcontentloaded",
                timeout=60000,
            )

            aguardar_login(page, credenciais)

        else:
            log("")
            log("============================================================")
            log("SESSÃO E-DESK JÁ AUTENTICADA - REUTILIZANDO")
            log("============================================================")
            log(f"URL REUTILIZADA: {page.url}")

        log("")
        log("****************************************")
        log("AUTENTICAÇÃO CONCLUÍDA")
        log("****************************************")
        log(f"URL AUTENTICADA: {page.url}")
        log("")

        # ============================================================
        # GUID DA SESSÃO
        # ============================================================

        guid_sessao = obter_guid_da_url(page.url)

        if not guid_sessao:
            raise RuntimeError(
                "Não foi possível obter o GUID da sessão após o login."
            )

        log(f"GUID DA SESSÃO: {guid_sessao}")

         # ============================================================
        # PROCESSAMENTO DOS TRABALHOS / HORAS
        #
        # REGRA:
        # Cada hora é uma operação completamente independente:
        #
        # Grid
        #   -> pesquisar solicitação
        #   -> abrir solicitação
        #   -> abrir trabalho correto
        #   -> abrir trabalho retroativo
        #   -> salvar UMA hora
        #   -> voltar para Grid
        #   -> repetir para a próxima hora
        #
        # Isso evita reutilizar páginas/solicitações/trabalhos da hora
        # anterior.
        # ============================================================

        total_trabalhos = len(trabalhos)
        delivery_results = []

        for indice_trabalho, trabalho in enumerate(trabalhos, start=1):

            solicitacao = str(
                trabalho.get("solicitacao", "") or ""
            ).strip()

            id_trabalho = str(
                trabalho.get("id_trabalho", "") or ""
            ).strip()

            horas = trabalho.get("horas", [])

            if not isinstance(horas, list):
                horas = []

            log("")
            log("############################################################")
            log(
                f"INICIANDO TRABALHO "
                f"{indice_trabalho} DE {total_trabalhos}"
            )
            log("############################################################")
            log(f"SOLICITAÇÃO: {solicitacao}")
            log(f"ID TRABALHO: {id_trabalho}")
            log(f"QUANTIDADE DE HORAS: {len(horas)}")
            log("")

            if not solicitacao:
                raise RuntimeError(
                    f"O TRABALHO {indice_trabalho} "
                    f"não possui solicitação."
                )

            if not id_trabalho:
                raise RuntimeError(
                    f"O TRABALHO {indice_trabalho} "
                    f"não possui idTrabalho."
                )

            total_horas = len(horas)

            if total_horas == 0:

                log(
                    f"Nenhuma hora enviada para "
                    f"{solicitacao} / {id_trabalho}."
                )

                continue

            # Abre a solicitação/trabalho uma única vez para todas as horas.
            # O retorno à Grid acontece apenas depois da última hora.
            acessar_minha_grid(page, guid_sessao)
            indice_hora = 1
            # ----------------------------------------------------
            # 2. IDENTIFICA A ATIVIDADE DESTA HORA
            # ----------------------------------------------------

            atividade_alvo = ""

            if isinstance(horas[0], dict):
                atividade_alvo = str(
                    horas[0].get("tarefa", "") or ""
                ).strip()

            log(
                f"ATIVIDADE ALVO: "
                f"{atividade_alvo or '[NÃO INFORMADA]'}"
            )

            # ----------------------------------------------------
            # 3. PESQUISA NOVAMENTE A SOLICITAÇÃO
            #
            # localizar_solicitacao já utiliza o campo Pesquisar
            # da Grid.
            # ----------------------------------------------------

            (
                pagina_grid,
                linha_grid,
                pagina_solicitacao_preaberta,
            ) = localizar_solicitacao(
                page,
                context,
                solicitacao,
                atividade_alvo
            )

            if pagina_grid is None or (
                linha_grid is None
                and pagina_solicitacao_preaberta is None
            ):
                raise RuntimeError(
                    f"Solicitação {solicitacao} "
                    f"não encontrada na Grid "
                    "ao abrir o trabalho."
                )

            # ----------------------------------------------------
            # 4. ABRE NOVAMENTE SOLICITAÇÃO / TRABALHO
            # ----------------------------------------------------

            log("")
            log(
                "ABRINDO SOLICITAÇÃO / "
                "TRABALHO PARA ESTA HORA..."
            )

            pagina_final = abrir_trabalho(
                pagina_grid,
                context,
                linha_grid,
                solicitacao,
                id_trabalho,
                pagina_solicitacao_preaberta
            )

            if pagina_final is None:
                raise RuntimeError(
                    f"Não foi possível abrir o trabalho "
                    f"{id_trabalho} da solicitação "
                    f"{solicitacao} para a "
                    "aberto."
                )

            # A partir daqui usamos SOMENTE a página
            # retornada para esta hora.
            pagina_hora = pagina_final
            referencia_horas = pagina_final._edesk_hours_reference

            # Always compare persisted rows before sending and after the batch.
            # A successful HTTP response alone is not a registration receipt.
            horas = [{**hour, 'data': obter_data_hora(hour),
                      'inicio': obter_inicio_hora(hour), 'fim': obter_fim_hora(hour)}
                     for hour in horas]

            def read_fresh_hours():
                nonlocal pagina_hora
                pagina_hora = preparar_tela_hora(pagina_hora, context, solicitacao, id_trabalho, referencia_horas)
                pagina_hora.goto(pagina_hora.url, wait_until='domcontentloaded', timeout=30000)
                pagina_hora = preparar_tela_hora(pagina_hora, context, solicitacao, id_trabalho, referencia_horas)
                pagina_hora.wait_for_timeout(300)
                return read_hours(pagina_hora)

            def submit_hour(hour, index, retry):
                nonlocal pagina_hora, pagina_hora_em_processamento, indice_hora_em_processamento
                hour['_saveOutcome'] = 'not_submitted'
                hour['_receiptRetry'] = retry
                try:
                    pagina_hora = preparar_tela_hora(pagina_hora, context, solicitacao, id_trabalho, referencia_horas)
                    pagina_hora_em_processamento = pagina_hora
                    indice_hora_em_processamento = index
                    salvar_hora(pagina_hora, hour, index, total_horas)
                except Exception as error:
                    log(f'Hora {index}: {error}. Conferindo a listagem antes de qualquer nova tentativa.')
                return hour['_saveOutcome']

            receipt = deliver_hours(horas, read_fresh_hours, submit_hour, hour_event, stage)
            delivery_results.append(receipt)
            log(receipt['message'])
            if not receipt['ok']:
                # A refused preflight is a normal receipt, not an exception.
                # Preserve the actual DOM for diagnosis before cleanup closes it.
                diagnostic_id = f"{time.strftime('%Y%m%d_%H%M%S')}_{indice_trabalho}"
                persistent_diagnostics = os.environ.get('EDESK_DIAGNOSTICS_DIR')
                if persistent_diagnostics:
                    try:
                        destination = Path(persistent_diagnostics)
                        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
                        artifact = {'solicitacao': solicitacao, 'trabalho': id_trabalho,
                                    'data': time.strftime('%Y-%m-%dT%H:%M:%S'),
                                    'tabela': pagina_hora.evaluate(GRID_DIAGNOSTIC_SCRIPT)}
                        target = destination / 'diagnostico-horas.json'
                        temporary = destination / 'diagnostico-horas.tmp'
                        temporary.write_text(json.dumps(artifact, ensure_ascii=False, indent=2), encoding='utf-8')
                        temporary.chmod(0o600)
                        temporary.replace(target)
                        log('Diagnostico persistente salvo em .edesk-local/diagnosticos da integracao.')
                    except Exception:
                        log('Nao foi possivel preservar o diagnostico persistente da tabela.')
                try:
                    pagina_hora.screenshot(path=str(LOGS_PATH / f'edesk_horas_pendentes_{diagnostic_id}.png'), full_page=True, timeout=15000)
                    (LOGS_PATH / f'edesk_horas_pendentes_{diagnostic_id}.html').write_text(pagina_hora.content(), encoding='utf-8')
                    log(f'Diagnostico da listagem preservado em: {LOGS_PATH}')
                except Exception:
                    log('Nao foi possivel preservar a tela de conferencia.')

            # Encerra páginas temporárias apenas após TODAS as horas.
            for pagina_aberta in list(context.pages):
                try:
                    if pagina_aberta is page or pagina_aberta.is_closed():
                        continue
                    url_temporaria = pagina_aberta.url or ""
                    if any(nome in url_temporaria for nome in (
                        "Solicitacao.aspx", "Trabalho.aspx", "TrabalhoRetroativo.aspx"
                    )):
                        pagina_aberta.close()
                except Exception as erro_fechamento:
                    log(f"Aviso ao fechar página temporária: {erro_fechamento}")

            if page.is_closed():
                raise RuntimeError("A página principal da Grid foi fechada.")
            acessar_minha_grid(page, guid_sessao)

            log("############################################################")
            log(
                f"TRABALHO {indice_trabalho} "
                f"DE {total_trabalhos} CONCLUÍDO"
            )
            log(f"SOLICITAÇÃO: {solicitacao}")
            log(f"TRABALHO: {id_trabalho}")
            log(f"HORAS PROCESSADAS: {total_horas}")
            log("############################################################")
            log("")

        # ============================================================
        # TODOS OS TRABALHOS
        # ============================================================

        log("")
        log("============================================================")
        log("TODOS OS TRABALHOS FORAM PROCESSADOS")
        log("============================================================")
        log(f"Total de trabalhos: {total_trabalhos}")

        if manter_navegador_aberto:
            log(
                "Modo 'manter navegador aberto' ativado."
            )
            aguardar_navegador(context)

        log("")
        log("============================================================")
        log("PROCESSAMENTO CONCLUÍDO COM SUCESSO" if all(item['ok'] for item in delivery_results)
            else "PROCESSAMENTO ENCERRADO COM HORAS PENDENTES DE CONFERÊNCIA")
        log("============================================================")
        log(
            f"TRABALHOS PROCESSADOS: "
            f"{total_trabalhos}"
        )
        log("============================================================")
        log("")

        receipt = {'operation': 'horas', 'ok': all(item['ok'] for item in delivery_results),
                   **{key: sum(item[key] for item in delivery_results)
                      for key in ('total', 'verified', 'retried', 'missing', 'uncertain')}}
        receipt['message'] = (f"{receipt['verified']} hora(s) conferidas no E-Desk. Nenhuma hora pendente. Cadastro finalizado com sucesso."
            if receipt['ok'] else f"{receipt['verified']} de {receipt['total']} hora(s) confirmadas; {receipt['missing']} não cadastradas e {receipt['uncertain']} sem comprovação. O sistema não repetiu envios sem confirmação de ausência para evitar duplicidade.")
        if not receipt['ok']:
            explanations = list(dict.fromkeys(item['message'] for item in delivery_results if not item['ok'] and item.get('attempted') == 0))
            if explanations:
                receipt['message'] += ' ' + ' '.join(explanations)
        print(json.dumps(receipt, ensure_ascii=False), flush=True)
        return 0 if receipt['ok'] else 1

    except Exception as erro:
        log("")
        log("============================================================")
        log("ERRO DURANTE A EXECUÇÃO")
        log("============================================================")
        log(f"{erro}")

        import traceback
        traceback_texto = traceback.format_exc()
        log(traceback_texto)

        pagina_diagnostico = pagina_hora_em_processamento
        if pagina_diagnostico is None and context is not None:
            for pagina in reversed(context.pages):
                try:
                    if not pagina.is_closed():
                        pagina_diagnostico = pagina
                        break
                except Exception:
                    continue

        if pagina_diagnostico is not None:
            sufixo_hora = (
                f"_hora_{indice_hora_em_processamento}"
                if indice_hora_em_processamento is not None
                else "_abertura"
            )
            identificador = (
                f"{time.strftime('%Y%m%d_%H%M%S')}{sufixo_hora}"
            )
            screenshot_path = LOGS_PATH / f"edesk_erro_{identificador}.png"
            html_path = LOGS_PATH / f"edesk_erro_{identificador}.html"

            try:
                pagina_diagnostico.screenshot(
                    path=str(screenshot_path),
                    full_page=True,
                    timeout=15000,
                )
                log(f"Captura da falha salva em: {screenshot_path}")
            except Exception as erro_screenshot:
                log(f"Não foi possível salvar captura da falha: {erro_screenshot}")

            try:
                html_path.write_text(
                    pagina_diagnostico.content(),
                    encoding="utf-8",
                )
                log(f"HTML da tela com falha salvo em: {html_path}")
            except Exception as erro_html:
                log(f"Não foi possível salvar HTML da falha: {erro_html}")

        if (
            context is not None
            and manter_navegador_aberto
            and not enviar
        ):
            try:
                aguardar_navegador(context)
            except Exception:
                pass

        raise

    finally:
        if not manter_navegador_aberto:
            fechar_playwright(
                context,
                playwright,
            )
            
if __name__ == "__main__":
    try:
        codigo = main()
        sys.exit(codigo if codigo is not None else 0)
    except KeyboardInterrupt:
        sys.exit(1)
    except Exception:
        sys.exit(1)
