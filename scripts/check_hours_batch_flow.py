"""Offline regression for several hours after Save returns to another page."""
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from unittest.mock import patch
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
sys.path.insert(0, str(ROOT / 'edesk_bot'))

with tempfile.TemporaryDirectory(prefix='hours-batch-', dir=ROOT / 'build') as temporary:
    os.environ['EDESK_DATA_DIR'] = temporary
    import edesk_horas as hours

    request_url = 'https://fixture.invalid/Portal/Solicitacao.aspx?GUID=fixture&solicitacao=226144'
    work_url = 'https://fixture.invalid/Portal/Trabalho.aspx?GUID=fixture&solicitacao=226144&id_trabalho=6'
    state = {'popup': False, 'expired': False}
    requests = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context()

        def route(incoming):
            requests.append((incoming.request.method, incoming.request.url))
            assert incoming.request.method == 'GET', 'No real or simulated Save POST is allowed'
            path = urlparse(incoming.request.url).path
            if path.endswith('/Solicitacao.aspx'):
                if state['expired']:
                    # A redirect may bypass Playwright routing. Keep the login
                    # navigation explicit so every request stays intercepted.
                    incoming.fulfill(status=200, content_type='text/html', body='<script>location.replace("https://fixture.invalid/login")</script>'); return
                action = ('setTimeout(()=>window.open(' if state['popup'] else 'setTimeout(()=>location.assign(')
                action += repr(work_url) + '),30)'
                body = ('<a role="tab" onclick="document.querySelector(\'#cph1_rpvTrabalhos\').style.display=\'block\'">Trabalhos (2)</a>'
                        '<div id="cph1_rpvTrabalhos" style="display:none"><table id="cph1_gvwTra">'
                        '<tr><th>ID</th><th>Descrição</th></tr><tr><td>6</td>'
                        '<td><a href="javascript:btnSelTra()">Implantação</a></td></tr></table></div>'
                        '<script>function btnSelTra(){' + action + '}</script>')
            elif path.endswith('/Trabalho.aspx'):
                body = '<p>Solicitação/Trabalho 226144/6</p>'
            elif path.endswith('/TrabalhoRetroativo.aspx'):
                body = '<input id="cph1_txtDatTem"><input id="cph1_txtHorIni"><input id="cph1_txtHorFin">'
            elif path == '/login':
                body = '<input type="password">'
            else:
                raise AssertionError(path)
            incoming.fulfill(status=200, content_type='text/html; charset=utf-8', body=body)

        context.route('**/*', route)
        with patch.object(hours, 'log'):
            count = 0
            for popup in [False, True]:
                state['popup'] = popup
                for returned_to in ['stay', 'request', 'work', 'closed', 'wrong-work', 'lost-form']:
                    page = context.new_page()
                    page.goto(work_url)
                    details = hours.extrair_dados_url(work_url)
                    page = hours.abrir_trabalho_retroativo(page, details)
                    reference = {'urlSolicitacao': request_url, 'dadosTrabalho': details}
                    saved = []
                    for index in range(3):
                        # Production invokes this before each Save, including the second hour.
                        page = hours.preparar_tela_hora(page, context, '226144', '6', reference)
                        assert hours.eh_trabalho_retroativo(page.url)
                        assert hours.extrair_dados_url(page.url)['id_trabalho'] == '6'
                        assert page.locator('#cph1_txtDatTem').is_visible()
                        saved.append(index)
                        if index == 2:
                            break
                        if returned_to == 'request':
                            page.evaluate('(url)=>setTimeout(()=>location.assign(url),30)', request_url)
                        elif returned_to == 'work':
                            page.goto(work_url)
                        elif returned_to == 'closed':
                            page.close()
                        elif returned_to == 'wrong-work':
                            page.goto(work_url.replace('id_trabalho=6', 'id_trabalho=7'))
                        elif returned_to == 'lost-form':
                            page.locator('#cph1_txtDatTem').evaluate('(element)=>element.remove()')
                    assert saved == [0, 1, 2], 'Earlier hours must not be repeated'
                    count += 1
                    for opened in list(context.pages):
                        opened.close()

            # A session failure before the second Save must stop, preserving the first result.
            page = context.new_page()
            page.goto(work_url)
            details = hours.extrair_dados_url(work_url)
            page = hours.abrir_trabalho_retroativo(page, details)
            reference = {'urlSolicitacao': request_url, 'dadosTrabalho': details}
            state['expired'] = True
            page.close()
            try:
                hours.preparar_tela_hora(page, context, '226144', '6', reference)
                raise AssertionError('Expired session must not allow the next Save')
            except RuntimeError as failure:
                assert 'sessão' in str(failure)
        browser.close()

print(f'HOURS_BATCH_FLOW_OK: {count} batches x 3 hours; return to request/work, closed page, wrong work, missing form, delayed popup and expired session; no Save POSTs')
