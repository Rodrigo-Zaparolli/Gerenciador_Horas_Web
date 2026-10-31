"""Exercise work import against delayed Telerik views, without real E-Desk access."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', str(ROOT / 'python/ms-playwright'))
sys.path.insert(0, str(ROOT / 'edesk_bot'))

from playwright.sync_api import sync_playwright
from edesk_conferencia import import_work_rows


def check():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            for delayed in (False, True):
                page = browser.new_page()
                page.set_content('''
                  <div>Solicitacao: 2260860 - Enterprise - Cliente</div>
                  <div class="rtsLevel1"><a class="rtsLink" href="#" onclick="openWorks();return false;">
                    <span><span>Trabalhos (2)</span></span></a></div>
                  <aside>Trabalhos (2)</aside>
                  <table id="cph1_gvwTra" style="display:none"></table>
                  <script>
                    function openWorks(){
                      window.clickCount=(window.clickCount||0)+1;
                      const table=document.querySelector('table');
                      table.style.display='table';
                      table.innerHTML='<tr><th>ID</th><th>Tipo de Trabalho</th><th>Tp. Estimado</th></tr>';
                      const populate=()=>table.innerHTML='<tr><th>ID</th><th>Tipo de Trabalho</th><th>Tp. Estimado</th></tr>'+
                        '<tr><td><a onclick="/*btnSelTra*/">3</a></td><td>Implantacao (OH)</td><td>02:30</td></tr>'+
                        '<tr><td><a onclick="/*btnSelTra*/">7</a></td><td>Desenvolvimento (OH)</td><td>04:00</td></tr>';
                      DELAY
                    }
                  </script>
                '''.replace('DELAY', 'setTimeout(populate, 400);' if delayed else 'populate();'))
                rows = import_work_rows(page, '2260860')
                assert [row['idTrabalho'] for row in rows] == ['3', '7'], rows
                assert [row['values']['estimatedHours'] for row in rows] == ['02:30', '04:00'], rows
                assert page.evaluate('window.clickCount') == 1
                page.close()
        finally:
            browser.close()
    print('IMPORT_READINESS_OK: main tab selected once, delayed rows read, real IDs and estimated hours preserved')


if __name__ == '__main__':
    check()
