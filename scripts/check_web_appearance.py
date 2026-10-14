"""Verify current themes and preference storage without signing in or sending data."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:8080')
parser.add_argument('--output', default='build/appearance-browser')
args = parser.parse_args()
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
results = []
themes = [('light', 'Claro'), ('dark', 'Escuro'), ('sand', 'Areia'),
          ('sage', 'Sálvia'), ('petroleum', 'Azul petróleo'), ('rose', 'Rosa suave'),
          ('ruby', 'Vermelho rubi'), ('black', 'Black'), ('slate', 'Azul ardósia'),
          ('ocean', 'Azul oceano'), ('azure', 'Azul celeste')]

def ready(page):
    page.locator('#app-loading').wait_for(state='detached', timeout=60000)
    placeholder = page.locator('flt-semantics-placeholder')
    if placeholder.count():
        placeholder.evaluate('(element) => element.click()')
    page.get_by_role('button', name='ENTRAR', exact=True).wait_for(timeout=30000)

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel='chrome', headless=True)
    for name, width, height in [('desktop', 1440, 900), ('mobile', 390, 844)]:
        context = browser.new_context(viewport={'width': width, 'height': height})
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(args.url, wait_until='networkidle', timeout=60000)
        ready(page)
        page.get_by_role('button', name='Escolher tema').wait_for()
        page.screenshot(path=str(output / f'login-light-{name}.png'))
        # A synthetic local draft verifies switching never rebuilds form State.
        email = page.get_by_role('textbox').first
        email.fill('tema@exemplo.invalid')
        page.wait_for_timeout(300)
        page.get_by_role('button', name='Escolher tema').click()
        page.get_by_role('menuitem', name='Escuro', exact=True).click()
        page.wait_for_timeout(1000)
        page.mouse.move(10, 10)
        page.get_by_role('button', name='Escolher tema').wait_for()
        # Flutter's semantics input mirrors controller text when it regains focus.
        email.click()
        page.wait_for_timeout(500)
        assert email.input_value() == 'tema@exemplo.invalid'
        assert page.evaluate("localStorage.getItem('gerenciador_horas.appearance')") == 'dark'
        page.screenshot(path=str(output / f'login-dark-{name}.png'))
        page.reload(wait_until='networkidle')
        ready(page)
        page.get_by_role('button', name='Escolher tema').wait_for()
        page.get_by_role('button', name='Criar nova conta', exact=True).click()
        page.get_by_role('textbox', name='Nome completo').wait_for(timeout=30000)
        page.screenshot(path=str(output / f'register-dark-{name}.png'))
        page.get_by_role('button', name='Escolher tema').click()
        page.get_by_role('menuitem', name='Areia', exact=True).click()
        page.wait_for_timeout(1000)
        assert page.evaluate("localStorage.getItem('gerenciador_horas.appearance')") == 'sand'
        page.mouse.move(10, 10)
        page.get_by_role('button', name='Escolher tema').wait_for()
        page.screenshot(path=str(output / f'register-sand-{name}.png'))
        page.reload(wait_until='networkidle')
        ready(page)
        assert page.evaluate("localStorage.getItem('gerenciador_horas.appearance')") == 'sand'
        for preference, label in themes:
            page.get_by_role('button', name='Escolher tema').click()
            page.get_by_role('menuitem', name=label, exact=True).click()
            page.wait_for_function('(expected) => localStorage.getItem("gerenciador_horas.appearance") === expected', arg=preference)
            page.mouse.move(10, 10)
            page.screenshot(path=str(output / f'login-{preference}-{name}.png'))
            page.reload(wait_until='networkidle')
            ready(page)
            assert page.evaluate("localStorage.getItem('gerenciador_horas.appearance')") == preference
        page.get_by_role('button', name='Escolher tema').click()
        page.get_by_role('menuitem', name='Claro', exact=True).click()
        page.wait_for_timeout(1000)
        assert page.evaluate("localStorage.getItem('gerenciador_horas.appearance')") == 'light'
        assert not errors, errors
        results.append({'viewport': name, 'themes': [preference for preference, _ in themes],
                        'draft_preserved': True, 'preference_after_reload': True,
                        'registration': 'ok', 'page_errors': errors})
        context.close()
    browser.close()

(output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(results, ensure_ascii=False))
