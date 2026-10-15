"""Offline browser: request -> exact work -> retroactive form. No real sends."""
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

with tempfile.TemporaryDirectory(prefix='hours-work-', dir=ROOT / 'build') as tmp:
    os.environ['EDESK_DATA_DIR'] = tmp
    import edesk_horas as hours
    from work_selection import resolve_work_selection
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        request_url = 'https://fixture.invalid/Portal/Solicitacao.aspx?GUID=fixture&solicitacao=226144'
        work_url = 'https://fixture.invalid/Portal/Trabalho.aspx?GUID=fixture&solicitacao=226144&id_trabalho=6'
        layouts = [
            '<td onclick="btnSelTra()">6</td><td onclick="btnSelTra()">Implantação</td>',
            '<td><a onclick="btnSelTra()">6</a></td><td>Implantação</td>',
            '<td>6</td><td><a href="javascript:btnSelTra()">Implantação</a></td>',
            '<td>6</td><td><button onclick="btnSelTra()">Abrir trabalho</button></td>',
        ]
        state = {'layout': layouts[0], 'delayed': False, 'redirect': False, 'popup': False}
        requests = []
        def route(r):
            requests.append((r.request.method, urlparse(r.request.url).path))
            assert r.request.method == 'GET', 'This regression must never save hours'
            path = urlparse(r.request.url).path
            if path.endswith('/Solicitacao.aspx'):
                row = '<tr>' + state['layout'] + '</tr>'
                body = '<a role="tab" onclick="document.querySelector(\'#cph1_rpvTrabalhos\').style.display=\'block\'">Trabalhos (2)</a><div id="cph1_rpvTrabalhos" style="display:none"><table id="cph1_gvwTra"><tr><th>Nº Trabalho</th><th>Descrição</th></tr>'
                body += ('' if state['delayed'] else row) + '</table></div>'
                action = ('setTimeout(()=>window.open("' + work_url + '","_blank"),100);') if state['popup'] else ('location.href="' + work_url + '";')
                body += '<script>function btnSelTra(){' + action + '}</script>'
                if state['delayed']:
                    import json
                    body += '<script>setTimeout(()=>document.querySelector("table").insertAdjacentHTML("beforeend",' + json.dumps(row) + '),300)</script>'
            elif path.endswith('/Trabalho.aspx'):
                body = '<p>Solicitação/Trabalho 226144/6</p>'
            elif path.endswith('/TrabalhoRetroativo.aspx'):
                if state['redirect']:
                    r.fulfill(status=302, headers={'Location': request_url}); return
                body = '<input id="cph1_txtDatTem">'
            else:
                raise AssertionError('Unexpected fixture URL: ' + path)
            r.fulfill(status=200, content_type='text/html; charset=utf-8', body=body)
        context.route('**/*', route)
        logs = []
        with patch.object(hours, 'log', side_effect=lambda value: logs.append(str(value))):
            for layout, popup in [(layout, popup) for layout in layouts for popup in [False, True]]:
                for delayed in [False, True]:
                    state.update(layout=layout, delayed=delayed, popup=popup)
                    page = context.new_page()
                    page.goto(request_url)
                    if not delayed:
                        assert resolve_work_selection(page.locator('table'), '6') is not None
                    work = hours.abrir_trabalho_na_solicitacao(page, context, '226144', '6')
                    assert work is not None and work.url == work_url, (layout, delayed, page.url, logs[-18:])
                    assert len(context.pages) == (2 if popup else 1), 'A work must open only once'
                    retro = hours.abrir_trabalho_retroativo(work, {})
                    assert retro.locator('#cph1_txtDatTem').is_visible()
                    for opened in list(context.pages):
                        opened.close()
            page = context.new_page()
            page.set_content('<table><tr><th>ID</th><th>Peso</th></tr><tr><td>7</td><td onclick="btnSelTra()">6</td></tr></table>')
            assert resolve_work_selection(page.locator('table'), '6') is None
            page.set_content('<table><tr><td onclick="btnSelTra()">6</td></tr><tr><td onclick="btnSelTra()">6</td></tr></table>')
            try:
                resolve_work_selection(page.locator('table'), '6')
                raise AssertionError('Ambiguous works must not be clicked')
            except RuntimeError:
                pass
            state.update(delayed=False, redirect=True)
            page.goto(work_url)
            try:
                hours.abrir_trabalho_retroativo(page, {})
                raise AssertionError('Redirect must not be accepted as retroactive form')
            except RuntimeError:
                pass
        browser.close()
print('HOURS_WORK_FLOW_OK: 16 layout/loading/popup cases, exact ID, ambiguity blocked, work and retroactive form verified; no POSTs or real E-Desk access')
