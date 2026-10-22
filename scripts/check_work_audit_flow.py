"""Isolated browser acceptance for the read-only E-Desk work audit."""
import json
import sys
from pathlib import Path
from unittest.mock import patch
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'edesk_bot'))
from playwright.sync_api import sync_playwright
from edesk_conferencia import audit_request, protect_read_only

base='https://fixture.invalid'
request_url=base+'/Solicitacao.aspx?solicitacao=226144'
writes=[]
visited=[]

def fixture(route):
    request=route.request
    if request.method=='POST':
        writes.append(request.post_data)
        return route.fulfill(body='Saved')
    path=urlparse(request.url).path
    if path.endswith('Solicitacao.aspx'):
        body='<div id="cph1_rpvTrabalhos"><table id="cph1_gvwTra"><tr><th>Número</th><th>Trabalho</th></tr>'
        for number in ['1','3','6']:
            url=base+f'/Trabalho.aspx?solicitacao=226144&id_trabalho={number}'
            body+=f'<tr><td><a href="#" onclick="/*btnSelTra*/window.open(\'{url}\');return false;">{number}</a></td><td>Etapa {number}</td></tr>'
        body+='</table></div>'
    elif path.endswith('TrabalhoRetroativo.aspx'):
        body='<table><tr><th>Data</th><th>Hora Inicial</th><th>Hora Final</th></tr><tr><td>22/10/2026</td><td>08:00</td><td>10:00</td></tr></table>'
    elif path.endswith('Trabalho.aspx'):
        visited.append(request.url)
        body='''<h1>Solicitação 226144 Trabalho 3</h1><table>
          <tr><td>Nome do trabalho</td><td><input value="Implantação Plugin"></td></tr>
          <tr><td>Situação</td><td><select><option>Em andamento</option></select></td></tr>
          <tr><td>Início ajustado</td><td><input value="01/10/2026"></td></tr>
          <tr><td>Término ajustado</td><td><input value="30/10/2026"></td></tr>
          <tr><td>%Realizado</td><td><input value="70"></td></tr></table>
          <button onclick="fetch('/save',{method:'POST',body:'cph1%24BtAtu=Salvar'})">Salvar</button>'''
    else:
        return route.fulfill(status=404,body='Not found')
    route.fulfill(content_type='text/html; charset=utf-8',body='<!doctype html><html><body>'+body+'</body></html>')

with sync_playwright() as p:
    browser=p.chromium.launch(headless=True, executable_path=p.chromium.executable_path)
    context=browser.new_context()
    context.route('**/*',fixture)
    context.route('**/*',protect_read_only)
    page=context.new_page();page.goto(request_url)
    with patch('edesk_comentario.acessar_minha_grid'), patch('edesk_comentario.localizar_solicitacao_validada',return_value=(page,None,page)), patch('edesk_comentario.abrir_solicitacao_para_comentario',return_value=page):
        result=audit_request(context,page,{'solicitacao':'226144','trabalhos':['3']},'test')
        assert len(result)==1 and result[0]['idTrabalho']=='3',result
        assert result[0]['values']=={'name':'Implantação Plugin','status':'Em andamento','start':'01/10/2026','end':'30/10/2026','percentage':'70'},result
        assert len(visited)==1 and 'id_trabalho=3' in visited[0],visited
        assert not writes,writes
        page.goto(request_url)
        result=audit_request(context,page,{'solicitacao':'226144','trabalhos':[]},'test')
        assert {row['idTrabalho'] for row in result}=={'1','3','6'},result
        def retro(work,_):
            work.goto(base+'/TrabalhoRetroativo.aspx?solicitacao=226144&id_trabalho=3')
            return work
        page.goto(request_url)
        with patch('edesk_horas.abrir_trabalho_retroativo',side_effect=retro):
            result=audit_request(context,page,{'solicitacao':'226144','trabalhos':['3']},'test',include_hours=True)
        assert result[0]['values']['hours']=='02:00',result
    assert not writes,writes
    probe=context.new_page();probe.goto(base+'/Trabalho.aspx?solicitacao=226144&id_trabalho=3')
    probe.evaluate("fetch('/save',{method:'POST',body:'__EVENTTARGET=cph1%24BtAtu'}).catch(()=>null)")
    assert not writes,'The read-only guard allowed a Save POST'
    browser.close()
print('WORK_AUDIT_BROWSER_OK: exact edited work, request enumeration, labeled values, retroactive hours, zero Save POSTs; no real E-Desk access',flush=True)
