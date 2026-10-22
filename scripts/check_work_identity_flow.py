"""An order/reference mismatch requires a proven original row selection."""
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
sys.path.insert(0, str(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'edesk_bot'))
with tempfile.TemporaryDirectory(prefix='work-identity-', dir=ROOT / 'build') as temporary:
    os.environ['EDESK_DATA_DIR'] = temporary
    import edesk_horas as hours
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        state = {'request': '2263800', 'work': '10', 'order': '6'}
        def route(incoming):
            assert incoming.request.method == 'GET'
            incoming.fulfill(content_type='text/html; charset=utf-8', body=(
                f'<p>Solicita&#231;&#227;o/Trabalho {state["request"]}/{state["work"]}</p>'
                '<table><tr><td><span>Ordem</span></td><td>'
                f'<input value="{state["order"]}"></td></tr></table>'))
        page.route('https://fixture.invalid/**', route)
        url = 'https://fixture.invalid/Portal/Trabalho.aspx?GUID=test&id_trabalho=opaque-work-10&solicitacao=opaque-request'
        with patch.object(hours, 'log'):
            page.goto(url)
            assert not hours.validar_tela_trabalho(page, '2263800', '6'), 'Order alone must not authorize a work'
            assert hours.validar_tela_trabalho(page, '2263800', '6', selecao_confirmada=True)
            assert hours.validar_tela_trabalho(page, '2263800', '6'), 'The proven mapping must survive revalidation'
            page.locator('input').fill('7')
            assert not hours.validar_tela_trabalho(page, '2263800', '6')
            page.locator('input').fill('6')
            page.goto(url.replace('opaque-work-10', 'another-work'))
            assert not hours.validar_tela_trabalho(page, '2263800', '6'), 'A different internal work cannot inherit the proof'
            state['request'] = '999'
            page.reload()
            assert not hours.validar_tela_trabalho(page, '2263800', '6', selecao_confirmada=True)
            state.update(request='2263800', work='60')
            page.reload()
            page.locator('table').evaluate('(e)=>e.remove()')
            assert not hours.validar_tela_trabalho(page, '2263800', '6', selecao_confirmada=True), '6 must never match 60'
            state.update(work='10')
            page.reload()
            page.locator('input').evaluate('(e)=>e.parentElement.insertAdjacentHTML("beforeend",\'<input value="6">\')')
            assert not hours.validar_tela_trabalho(page, '2263800', '6', selecao_confirmada=True), 'Ambiguous order fields must fail closed'
        browser.close()
print('WORK_IDENTITY_FLOW_OK: proven order/reference mapping; wrong request, changed identity, numeric prefix, ambiguous or unproven order rejected; no POSTs')
