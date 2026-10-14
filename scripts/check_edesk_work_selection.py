"""Validate work selection on isolated pages; never contact E-Desk."""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'browser_extension/page-dom.js').read_text(encoding='utf-8')
source = source.replace('export async function', 'async function', 1)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path=str(
        ROOT / 'python/ms-playwright/chromium-1187/chrome-win/chrome.exe'))
    page = browser.new_page()
    page.set_content('''<ul><li class="rtsLI" onclick="window.selectedTab='work'">
      <span class="rtsTxt">Trabalhos (7)</span></li>
      <li class="rtsLI" onclick="window.selectedTab='other'">
      <span class="rtsTxt">Trabalhos concluídos (3)</span></li></ul>''')
    page.add_script_tag(content=source)
    result = page.evaluate("edeskDom('tab', {name:'Trabalhos'})")
    assert 'error' not in result, result
    assert page.evaluate('window.selectedTab') == 'work'
    page.set_content('''<table id="cph1_gvwTra"><tr>
      <td onclick="window.btnSelTra=4;window.selected=4">4</td>
      <td onclick="window.btnSelTra=4;window.selected=4">4</td>
      <td onclick="window.btnSelTra=4;window.selected=4">Treinamento Catalog</td>
    </tr></table>''')
    page.add_script_tag(content=source)
    result = page.evaluate("edeskDom('open-work', {id:'4'})")
    assert 'error' not in result, result
    assert page.evaluate('window.selected') == 4
    page.evaluate('''() => {
      window.selected=null;
      const row=document.querySelector('tr').cloneNode(true);
      document.querySelector('table').append(row);
    }''')
    result = page.evaluate("edeskDom('open-work', {id:'4'})")
    assert 'error' in result, result
    assert page.evaluate('window.selected') is None
    browser.close()
print('WORK_SELECTION_OK: repeated cells in one row accepted; ambiguous rows blocked')
