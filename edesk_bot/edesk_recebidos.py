"""Read the current user's Minha Grid; no work creation or updates in E-Desk."""
import json
import sys

GRID = r'''() => {
  const table=document.querySelector('#ctl00_cph1_hgrSol_ctl00');
  const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
  const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
  if(!visible(table))return {rows:[],complete:false,reason:'Tabela da Minha Grid nao identificada.'};
  const rows=[...table.rows].filter(r=>r.closest('table')===table);
  const header=rows.find(r=>r.querySelector('th'));
  if(!header)return {rows:[],complete:false,reason:'Cabecalho da Minha Grid nao identificado.'};
  const names=[...header.cells].map(c=>norm(c.innerText));
  const aliases={solicitacao:['solicitacao','numerodasolicitacao','numerosolicitacao','nsolicitacao','numero','solicitacaotrabalho'],
    idTrabalho:['trabalho','numerodotrabalho','numerotrabalho','ntrabalho'],
    client:['cliente','empresa','razaosocial'],serviceType:['tipodeservico','servico','produto','tipo'],
    leader:['lider','liderdoprojeto','liderprojeto'],hours:['horasprevistas','horasestimadas','tempoprevisto'],
    name:['atividade','descricaodotrabalho','nomedotrabalho','descricao'],status:['situacao','status']};
  const columns=Object.fromEntries(Object.entries(aliases).map(([k,values])=>[k,names.findIndex(n=>values.includes(n))]));
  if(columns.solicitacao<0)return {rows:[],complete:false,reason:'Coluna de solicitacao nao reconhecida.'};
  const result={rows:[],complete:true,index:1};
  const scope=table.closest('.RadGrid')||table;
  const pagers=[...scope.querySelectorAll('.rgPager,.pager'),...rows.filter(r=>r.querySelector('a[href*="Page$"]'))];
  const commands=[...new Set(pagers.flatMap(r=>[...r.querySelectorAll('a,button,input')]))].filter(visible).map(e=>{
    let arg=(((e.getAttribute('href')||'')+' '+(e.getAttribute('onclick')||'')).match(/Page\$(First|Next|Last|Previous|Prev|\d+)/i)||[])[1];
    if(arg&&!/^\d+$/.test(arg))arg=arg[0].toUpperCase()+arg.slice(1).toLowerCase();
    if(e.matches('.rgPageNext'))arg='Next';if(e.matches('.rgPageFirst'))arg='First';
    const disabled=e.disabled||e.getAttribute('aria-disabled')==='true'||/disabled/i.test(e.className);
    return {e,arg,disabled};
  });
  const current=scope.querySelector('.rgCurrentPage')?.textContent.trim();
  if(current&&/^\d+$/.test(current))result.index=Number(current);
  else if(pagers.length){
    const numbers=[...new Set(pagers.flatMap(r=>[...r.querySelectorAll('span')]).filter(e=>!e.closest('a')&&/^\d+$/.test(e.textContent.trim())).map(e=>Number(e.textContent.trim())))];
    if(numbers.length===1)result.index=numbers[0];else result.complete=false;
  }
  const first=commands.find(c=>!c.disabled&&(c.arg==='First'||c.arg==='1'));
  const next=commands.find(c=>!c.disabled&&c.arg==='Next')||commands.filter(c=>!c.disabled&&/^\d+$/.test(c.arg||'')&&Number(c.arg)>result.index).sort((a,b)=>Number(a.arg)-Number(b.arg))[0];
  for(const e of document.querySelectorAll('[data-gh-inbox-page]'))e.removeAttribute('data-gh-inbox-page');
  if(first){first.e.setAttribute('data-gh-inbox-page','first');result.first='[data-gh-inbox-page="first"]';}
  if(next){next.e.setAttribute('data-gh-inbox-page','next');result.next='[data-gh-inbox-page="next"]';}
  if(commands.some(c=>!c.arg&&!c.e.matches('.rgCurrentPage,.rgPagePrev,.rgPageLast')))result.complete=false;
  for(const row of rows){
    if(row===header||row.querySelector('th')||pagers.includes(row))continue;
    const cells=[...row.cells];
    if(cells.length<=columns.solicitacao)continue;
    const ref=cells[columns.solicitacao].innerText.trim();
    const match=ref.match(/^(\d+)(?:\s*\/\s*(\d+))?$/);
    if(!match){if(!/nenhum|semregistro|norecord/.test(norm(row.innerText)))result.complete=false;continue;}
    const item={solicitacao:match[1]};
    for(const [key,index]of Object.entries(columns))if(key!=='solicitacao'&&index>=0&&cells[index])item[key]=cells[index].innerText.trim();
    if(match[2])item.idTrabalho=match[2];
    if(item.idTrabalho&&!/^\d+$/.test(item.idTrabalho))delete item.idTrabalho;
    result.rows.push(item);
  }
  return result;
}'''


def read_inbox(page, max_pages=100):
    collected, seen = {}, set()
    for step in range(max_pages):
        page.wait_for_function("() => document.readyState!=='loading'&&!window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()", timeout=20000)
        current=page.evaluate(GRID)
        if step==0 and current.get('index',1)>1:
            if not current.get('first'):
                return {'rows':[],'complete':False,'reason':'Nao foi possivel consultar a primeira pagina.'}
            page.locator(current['first']).click()
            page.wait_for_timeout(300)
            current=page.evaluate(GRID)
            if current.get('index')!=1:
                return {'rows':[],'complete':False,'reason':'A paginacao nao retornou ao inicio.'}
        identity=(current.get('index'),json.dumps(current.get('rows',[]),sort_keys=True))
        if identity in seen:
            return {'rows':list(collected.values()),'complete':False,'reason':'A paginacao nao avancou.'}
        seen.add(identity)
        for item in current['rows']:
            key=(item['solicitacao'],item.get('idTrabalho',''))
            if key in collected and collected[key]!=item:
                return {'rows':list(collected.values()),'complete':False,'reason':'Dados divergentes para a mesma referencia.'}
            collected[key]=item
        if current.get('complete') is not True:
            return {'rows':list(collected.values()),'complete':False,'reason':current.get('reason','Parte da Minha Grid nao foi reconhecida.')}
        if not current.get('next'):
            return {'rows':list(collected.values()),'complete':True}
        page.locator(current['next']).click()
        page.wait_for_timeout(300)
    return {'rows':list(collected.values()),'complete':False,'reason':'Limite de paginas atingido.'}


def main():
    from edesk_comentario import (carregar_request, obter_credenciais_edesk, obter_url,
                                 aguardar_login, obter_guid_da_url, acessar_minha_grid)
    from config import PROFILE_DIR, HEADLESS, restore_session_cookies, save_session_cookies
    from edesk_conferencia import protect_read_only
    from playwright.sync_api import sync_playwright
    data=carregar_request()
    if data.get('enviar') is not False:
        raise ValueError('A busca de recebidos permite apenas consulta.')
    with sync_playwright() as p:
        context=p.chromium.launch_persistent_context(str(PROFILE_DIR),headless=HEADLESS,viewport=None)
        try:
            context.route('**/*',protect_read_only)
            restore_session_cookies(context)
            page=context.pages[0] if context.pages else context.new_page()
            page.goto(obter_url(data),wait_until='domcontentloaded',timeout=60000)
            aguardar_login(page,credenciais=obter_credenciais_edesk(data))
            guid=obter_guid_da_url(page.url)
            if not guid:raise RuntimeError('Sessao nao identificada.')
            save_session_cookies(context)
            acessar_minha_grid(page,guid)
            search=page.locator('#cph1_txtSol')
            if search.count()==1 and search.input_value().strip():
                search.fill('')
                page.locator('#cph1_btnLocSol').click(timeout=15000)
                page.wait_for_timeout(500)
            result=read_inbox(page)
        finally:
            context.close()
    print(json.dumps({'ok':True,'operation':'recebidos',**result,
        'message':'Minha Grid consultada. Nenhum trabalho foi cadastrado automaticamente.'},ensure_ascii=False),flush=True)
    return 0


if __name__=='__main__':
    try:sys.exit(main())
    except Exception:
        print(json.dumps({'ok':False,'operation':'recebidos','message':'Nao foi possivel consultar a Minha Grid. Confira a integracao e o login.'}),flush=True)
        sys.exit(1)
