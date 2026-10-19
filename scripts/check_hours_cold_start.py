"""Cold request page -> exact work -> retroactive form, without any Save POST."""
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from unittest.mock import patch
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
sys.path.insert(0, str(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'edesk_bot'))

with tempfile.TemporaryDirectory(prefix='hours-cold-', dir=ROOT / 'build') as temporary:
    os.environ['EDESK_DATA_DIR'] = temporary
    import edesk_horas as hours
    request_url = 'https://fixture.invalid/Portal/Solicitacao.aspx?GUID=test&solicitacao=226144'
    work_url = 'https://fixture.invalid/Portal/Trabalho.aspx?GUID=test&solicitacao=226144&id_trabalho=6'
    state = {'case': '', 'popup': False, 'cold': True}
    calls = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()

        def respond(route):
            assert route.request.method == 'GET', 'No hours or comment may be saved by this regression'
            calls.append(route.request.url)
            path = urlparse(route.request.url).path
            if path.endswith('/Solicitacao.aspx'):
                busy = state['cold'] and state['case'] == 'initial_busy'
                ajax = state['cold'] and state['case'] == 'ajax_tab'
                hidden = state['case'] == 'hidden_controls'
                hidden_control = '<a style="display:none" onclick="btnSelTraWrong()">6</a>' if hidden else ''
                row = '<tr><td>6</td><td>' + hidden_control + '<button id="select-work" onclick="btnSelTra()">Implantação</button></td></tr>'
                if hidden:
                    row += '<tr style="display:none"><td>6</td><td onclick="btnSelTraWrong()">Implantação antiga</td></tr>'
                action = f'window.open({work_url!r},"_blank")' if state['popup'] else f'location.assign({work_url!r})'
                html = f'''<a style="display:none">Trabalhos (2)</a>
                  <a role="tab" onclick="openTab()">Trabalhos (2)</a>
                  <div id="cph1_rpvTrabalhos" style="display:none"><table id="cph1_gvwTra">
                  <tr><th>ID</th><th>Descrição</th></tr>{row}</table></div>
                  <script>
                  window.busy={str(busy).lower()}; window.premature=false;
                  window.Sys={{WebForms:{{PageRequestManager:{{getInstance:()=>({{get_isInAsyncPostBack:()=>window.busy}})}}}}}};
                  function openTab(){{
                    if(window.busy){{window.premature=true;return;}}
                    document.querySelector('#cph1_rpvTrabalhos').style.display='block';
                    if({str(ajax).lower()}){{window.busy=true;document.querySelector('#select-work').disabled=true;
                      setTimeout(()=>{{window.busy=false;document.querySelector('#select-work').disabled=false}},350);}}
                  }}
                  function btnSelTra(){{if(window.busy){{window.premature=true;return;}} {action};}}
                  function btnSelTraWrong(){{throw Error('Hidden control must not be clicked');}}
                  setTimeout(()=>{{window.busy=false}},700);
                  </script>'''
            elif path.endswith('/Trabalho.aspx'):
                html = '<p>Solicitação/Trabalho 226144/6</p>'
            elif path.endswith('/TrabalhoRetroativo.aspx'):
                html = '<input id="cph1_txtDatTem"><input id="cph1_txtHorIni"><input id="cph1_txtHorFin">'
            else:
                raise AssertionError('Unexpected external URL')
            route.fulfill(status=200, content_type='text/html; charset=utf-8', body=html)

        context.route('**/*', respond)
        with patch.object(hours, 'log'):
            for case in ['initial_busy', 'ajax_tab', 'hidden_controls']:
                for popup in [False, True]:
                    for cold in [True, False]:
                        state.update(case=case, popup=popup, cold=cold)
                        page = context.new_page()
                        page.goto(request_url)
                        work = hours.abrir_trabalho_na_solicitacao(page, context, '226144', '6')
                        assert work and hours.validar_tela_trabalho(work, '226144', '6')
                        if popup:
                            assert page.evaluate('window.premature') is False
                        retro = hours.abrir_trabalho_retroativo(work, hours.extrair_dados_url(work.url))
                        assert retro.locator('#cph1_txtDatTem').is_visible()
                        for opened in list(context.pages):
                            opened.close()
        browser.close()
print('HOURS_COLD_START_OK: 12 cold/warm/Ajax/hidden-control/popup cases; correct work and retroactive form; no POSTs')
