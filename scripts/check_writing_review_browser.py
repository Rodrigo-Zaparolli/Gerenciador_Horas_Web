"""Exercise the compiled Flutter review UI, without real user data or accounts."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), partial(
    Handler, directory=str(ROOT / 'build/writing-review-browser')))
Thread(target=server.serve_forever, daemon=True).start()
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=str(
            ROOT / 'python/ms-playwright/chromium-1187/chrome-win/chrome.exe'))
        for width, height in [(1200, 800), (390, 700)]:
            page = browser.new_page(viewport={'width': width, 'height': height})
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.goto(f'http://127.0.0.1:{server.server_port}', wait_until='networkidle')
            field = page.get_by_role('textbox', name='Descrição das horas')
            field.click(timeout=60000)
            page.get_by_role('button', name='Revisar escrita').click()
            review = page.locator('textarea[aria-label="Texto para revisar em português"]')
            review.wait_for()
            assert review.get_attribute('lang') == 'pt-BR'
            assert review.evaluate('(el) => el.spellcheck') is True
            assert review.input_value() == 'Descricao do servico'
            assert review.evaluate('''el => {
                const e = new MouseEvent('contextmenu', {bubbles:true, cancelable:true});
                el.dispatchEvent(e); return !e.defaultPrevented;
            }'''), 'Browser suggestions menu must remain available'
            review.fill('Descrição do serviço')
            page.get_by_role('button', name='Cancelar', exact=True).click()
            field.click()
            page.get_by_role('button', name='Revisar escrita').click()
            assert review.input_value() == 'Descricao do servico'
            review.fill('Descrição do serviço')
            page.get_by_role('button', name='Aplicar correções').click()
            page.get_by_text('Resultado: Descrição do serviço', exact=True).wait_for()
            assert not errors, errors
            page.close()
        browser.close()
finally:
    server.shutdown()
    server.server_close()
print('WRITING_REVIEW_BROWSER_OK: desktop/mobile, Portuguese spellcheck, native menu, cancel, apply and onChanged; dictionary suggestions depend on browser settings')
