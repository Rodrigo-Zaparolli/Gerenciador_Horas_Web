"""Read-only, isolated Minha Grid fixtures; no real E-Desk access."""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'edesk_bot'))
from edesk_recebidos import read_inbox
from edesk_conferencia import protect_read_only

with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path=p.chromium.executable_path)
    context=browser.new_context();calls=[]
    def fixture(route):
        assert route.request.method=='GET','The inbox must not save or update any work'
        page=2 if 'page=2' in route.request.url else 1
        calls.append(page)
        request='226144/3' if page==1 else '226144/6'
        pager='<span>1</span><a href="/grid?page=2" onclick="/* Page$2 */">2</a>' if page==1 else '<a href="/grid?page=1" onclick="/* Page$1 */">1</a><span>2</span>'
        route.fulfill(content_type='text/html; charset=utf-8',body=f'''<div class="RadGrid"><table id="ctl00_cph1_hgrSol_ctl00">
        <tr><th>Solicitação/Trabalho</th><th>Cliente</th><th>Tipo de serviço</th><th>Líder</th></tr>
        <tr><td>{request}</td><td>Cliente</td><td>Professional</td><td>Líder</td></tr>
        <tr class="rgPager"><td colspan="4">{pager}</td></tr></table></div>''')
    context.route('**/*',fixture);context.route('**/*',protect_read_only)
    page=context.new_page();page.goto('https://fixture.invalid/grid?page=2')
    result=read_inbox(page)
    assert result['complete'] is True,result
    assert [r['idTrabalho'] for r in result['rows']]==['3','6'],result
    assert result['rows'][0]['leader']=='Líder',result
    assert calls==[2,1,2],calls
    page.set_content('<table id="ctl00_cph1_hgrSol_ctl00"><tr><th>Campo desconhecido</th></tr><tr><td>226144</td></tr></table>')
    result=read_inbox(page)
    assert result['complete'] is False and result['rows']==[],result
    page.set_content('<table id="ctl00_cph1_hgrSol_ctl00"><tr><th>Solicitação</th></tr><tr><td>Nenhum registro</td></tr></table>')
    result=read_inbox(page)
    assert result['complete'] is True and result['rows']==[],result
    browser.close()
print('RECEIVED_GRID_BROWSER_OK: personal grid, pagination reset, real work IDs, required headers, empty results, zero Save POSTs',flush=True)
