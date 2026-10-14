"""Smoke check the compiled site without signing in or changing remote data."""
import argparse
import json
from pathlib import Path

from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://localhost:8080')
parser.add_argument('--output', default='build/web-validation')
args = parser.parse_args()
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
results = []

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel='chrome', headless=True)
    for name, width, height in [('desktop', 1440, 900), ('mobile', 390, 844)]:
        page = browser.new_page(viewport={'width': width, 'height': height})
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(args.url, wait_until='networkidle', timeout=60000)
        page.locator('#app-loading').wait_for(state='detached', timeout=60000)
        page.locator('flt-semantics-placeholder').evaluate('(element) => element.click()')
        page.get_by_role('button', name='ENTRAR', exact=True).wait_for(timeout=30000)
        page.screenshot(path=str(output / f'login-{name}.png'), full_page=True)
        page.get_by_role('button', name='Criar nova conta', exact=True).click()
        page.get_by_role('textbox', name='Nome completo').wait_for(timeout=30000)
        page.screenshot(path=str(output / f'cadastro-{name}.png'), full_page=True)
        page.get_by_role('button', name='Voltar', exact=True).click()
        page.get_by_role('button', name='ENTRAR', exact=True).wait_for(timeout=30000)
        assert not errors, errors
        results.append({'viewport': name, 'login': 'ok', 'cadastro': 'ok', 'page_errors': errors})
        page.close()
    browser.close()

(output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(results, ensure_ascii=False))
