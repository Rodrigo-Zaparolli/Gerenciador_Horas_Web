"""Read-only work inspection. Never fill a work field or invoke Save."""
import json
import re
import sys
import time
from urllib.parse import parse_qs

from config import HEADLESS, PROFILE_DIR, restore_session_cookies, save_session_cookies
from send_progress import completed, stage


def mutation_request(request):
    if request.method != 'POST':
        return False
    data = parse_qs(request.post_data or '', keep_blank_values=True)
    commands = list(data) + data.get('__EVENTTARGET', []) + data.get('__EVENTARGUMENT', [])
    return any(re.search(r'btatu|btsalv|btexc|btdelete|salvar|excluir|gravar|(?:^|\$)save(?:$|\$)', item, re.I)
               for item in commands)


def protect_read_only(route):
    if mutation_request(route.request):
        route.abort('blockedbyclient')
    else:
        route.fallback()


READ_FIELDS = r'''() => {
  const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
  const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9%]/g,'');
  const aliases={name:['trabalho','nomedotrabalho','descricao','descricaodotrabalho','atividade'],
    status:['situacao','situacaodotrabalho','status','statusdotrabalho'],
    start:['inicioajustado','datadeinicioajustada','datainicialajustada','inicioprevisto','datainicialprevista'],
    end:['terminoajustado','datafinalajustada','datadeterminoajustada','terminoprevisto','datafinalprevista'],
    percentage:['%realizado','percentualrealizado','percentualdeconclusao'],
    estimatedHours:['horasprevistas','horasestimadas','tempoprevisto','tempoestimado','horasprevistashhmm','horasestimadashhmm','tempoprevistohhmm','tempoestimadohhmm'],
    leader:['lider','liderdoprojeto','liderprojeto'],
    serviceType:['tipodeservico','servico','produto'],client:['cliente','empresa','razaosocial','nomedocliente','clienteempresa']};
  const values={};
  for(const [field,labels] of Object.entries(aliases)){
    const found=new Set();
    for(const label of document.querySelectorAll('label,td,span')){
      if(!visible(label)||!labels.includes(norm(label.textContent)))continue;
      const controls=new Set();
      if(label.htmlFor)controls.add(document.getElementById(label.htmlFor));
      const cell=label.closest('td');
      if(cell?.nextElementSibling)controls.add(cell.nextElementSibling);
      if(label.parentElement&&!['BODY','TABLE','TR'].includes(label.parentElement.tagName))
        for(const e of label.parentElement.querySelectorAll('input,select,textarea'))controls.add(e);
      for(const e of controls){
        if(!visible(e))continue;
        const inputs=e.matches('input,select,textarea')?[e]:[...e.querySelectorAll('input,select,textarea')].filter(visible);
        for(const item of inputs){
          const value=item.tagName==='SELECT'?item.selectedOptions[0]?.textContent:item.value;
          if(value?.trim())found.add(value.trim());
        }
        if(!inputs.length&&e.textContent.trim())found.add(e.textContent.trim());
      }
    }
    if(found.size===1)values[field]=[...found][0];
  }
  return values;
}'''


class AuditLookupError(RuntimeError):
    MESSAGES = {
        'grid': 'Nao foi possivel abrir a Minha Grid do E-Desk.',
        'search_request': 'Nao foi possivel localizar a solicitacao na Minha Grid.',
        'open_request': 'A solicitacao nao terminou de abrir no E-Desk.',
        'work_tab': 'A solicitacao abriu, mas a aba Trabalhos nao ficou disponivel.',
        'work_table': 'A aba Trabalhos foi acionada, mas a tabela de etapas nao carregou.',
        'work_pagination': 'A lista de trabalhos esta paginada. A importacao foi interrompida para nao omitir etapas.',
        'work_numbers': 'Nenhum numero real de trabalho foi reconhecido na tabela da solicitacao.',
    }

    def __init__(self, code):
        self.code = code
        super().__init__(self.MESSAGES[code])


def show_works(page):
    page.wait_for_load_state('domcontentloaded', timeout=15000)
    page.wait_for_function("() => !window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()", timeout=15000)
    table = page.locator('#cph1_gvwTra')
    # A visible container can still contain an inactive/hidden Telerik tab.
    # Only the actual work table proves that the tab has finished opening.
    if not table.count() or not table.first.is_visible():
        deadline = time.monotonic() + 15
        tabs = []
        while time.monotonic() < deadline:
            tabs = [tab for tab in page.get_by_text(re.compile(r'^Trabalhos\s*(?:\(\d+\))?$')).all() if tab.is_visible()]
            if tabs:
                break
            page.wait_for_timeout(100)
        if len(tabs) != 1:
            raise AuditLookupError('work_tab')
        try:
            tabs[0].click(timeout=15000)
        except Exception as error:
            raise AuditLookupError('work_tab') from error
    try:
        table.wait_for(state='visible', timeout=15000)
        page.wait_for_function("() => !window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()", timeout=15000)
    except Exception as error:
        raise AuditLookupError('work_table') from error


def work_numbers(page):
    show_works(page)
    # Unknown pagination must never be reported as a complete request.
    table = page.locator('#cph1_gvwTra')
    if table.locator('a[href*="Page$"],.rgPager').count():
        raise AuditLookupError('work_pagination')
    return table.evaluate(r'''table => {
      const ids=[];
      for(const row of table.rows){
        if(row.closest('table')!==table||!row.getClientRects().length)continue;
        const links=[...row.querySelectorAll('[onclick*="btnSelTra"],a[href*="btnSelTra"]')];
        if(!links.length)continue;
        const exact=links.map(e=>e.innerText.trim()).filter(v=>/^\d+$/.test(v));
        const id=exact[0]||[...row.cells].map(e=>e.innerText.trim()).find(v=>/^\d+$/.test(v));
        if(id)ids.push(id);
      }
      return [...new Set(ids)];
    }''')


def import_work_rows(page, solicitation):
    """Read the request's visible work grid; never infer IDs from Ordem."""
    show_works(page)
    table = page.locator('#cph1_gvwTra')
    if table.locator('a[href*="Page$"],.rgPager').count():
        raise AuditLookupError('work_pagination')
    result = table.evaluate(r'''table => {
      const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
      const rows=[...table.rows].filter(r=>r.closest('table')===table&&r.getClientRects().length);
      const header=rows.find(r=>[...r.cells].some(c=>norm(c.innerText)==='tipodetrabalho'));
      if(!header)return {error:'Nao foi encontrada a coluna Tipo de Trabalho.'};
      const labels=[...header.cells].map(c=>norm(c.innerText));
      const column=aliases=>labels.map((v,i)=>aliases.includes(v)?i:-1).filter(i=>i>=0);
      const name=column(['tipodetrabalho']);
      const hours=column(['tpestimado','tempoestimado','horasprevistas','horasestimadas']);
      const start=column(['inicio']),end=column(['termino','fim']);
      if(name.length!==1||hours.length!==1)return {error:'As colunas Tipo de Trabalho e Tempo Estimado nao foram reconhecidas sem ambiguidade.'};
      const output=[];
      for(const row of rows){
        const links=[...row.querySelectorAll('[onclick*="btnSelTra"],a[href*="btnSelTra"]')];
        if(!links.length)continue;
        const ids=[...new Set(links.map(e=>e.innerText.trim()).filter(v=>/^\d+$/.test(v)))];
        if(ids.length!==1)return {error:'O ID real de um trabalho nao foi reconhecido; Ordem nao sera usada como ID.'};
        const text=i=>row.cells[i]?.innerText.trim()||'';
        const title=text(name[0]),estimated=text(hours[0]);
        if(!title||!/^\d{1,5}:[0-5]\d$/.test(estimated))return {error:'Confira o tipo e o tempo estimado do trabalho '+ids[0]+'.'};
        const date=indices=>indices.length===1?(text(indices[0]).match(/^\d{2}\/\d{2}\/\d{4}/)?.[0]||''):'';
        output.push({idTrabalho:ids[0],values:{name:title,estimatedHours:estimated,start:date(start),end:date(end)}});
      }
      return {rows:output};
    }''')
    if result.get('error'):
        raise RuntimeError(result['error'])
    rows = result.get('rows', [])
    if not rows:
        raise AuditLookupError('work_numbers')
    if len({row['idTrabalho'] for row in rows}) != len(rows):
        raise RuntimeError('A tabela retornou IDs de trabalho repetidos.')
    heading = page.evaluate(r'''() => {
      const match=document.body.innerText.match(/(?:^|\n)\s*Solicita[cç][aã]o:\s*(\d+)\s*-\s*([^\r\n]+)/i);
      return match ? {request:match[1],title:match[2].trim()} : null;
    }''')
    if heading:
        if str(heading['request']) != str(solicitation):
            raise RuntimeError('O cabecalho pertence a outra solicitacao.')
        for row in rows:
            row['values']['requestTitle'] = heading['title']
    return [{**row, 'solicitacao': solicitation} for row in rows]


def audit_request(context, grid, target, guid, include_hours=False, import_grid=False):
    from edesk_comentario import (acessar_minha_grid, abrir_solicitacao_para_comentario,
                                  localizar_solicitacao_validada)
    from edesk_horas import abrir_trabalho_na_solicitacao, validar_tela_trabalho, abrir_trabalho_retroativo, extrair_dados_url
    from hour_receipt import read_hours
    solicitation = target['solicitacao']
    phase = 'grid'
    try:
        acessar_minha_grid(grid, guid)
        phase = 'search_request'
        page, row, opened = localizar_solicitacao_validada(grid, context, solicitation)
        phase = 'open_request'
        if import_grid:
            from edesk_horas import abrir_trabalho
            request_page = abrir_trabalho(page, context, row, solicitation, '',
                pagina_solicitacao_preaberta=opened, abrir_retroativo=False,
                somente_solicitacao=True, validar_solicitacao=show_works)
        else:
            request_page = abrir_solicitacao_para_comentario(page, context, row, solicitation, opened)
        request_url = request_page.url
        if import_grid:
            return import_work_rows(request_page, solicitation)
        numbers = target.get('trabalhos') or work_numbers(request_page)
    except AuditLookupError:
        raise
    except Exception as error:
        raise AuditLookupError(phase) from error
    if not numbers:
        raise AuditLookupError('work_numbers')
    rows = []
    for number in numbers:
        result = {'solicitacao': solicitation, 'idTrabalho': str(number), 'values': {}}
        try:
            if request_page.is_closed():
                request_page = context.new_page()
            request_page.goto(request_url, wait_until='domcontentloaded', timeout=30000)
            show_works(request_page)
            work = abrir_trabalho_na_solicitacao(request_page, context, solicitation, number)
            if work is None or not validar_tela_trabalho(work, solicitation, number):
                raise RuntimeError('O trabalho solicitado nao foi localizado com sua chave exata.')
            result['values'] = work.evaluate(READ_FIELDS)
            if include_hours:
                try:
                    retro = abrir_trabalho_retroativo(work, extrair_dados_url(work.url))
                    receipt = read_hours(retro)
                    if receipt.get('complete') is True:
                        total = 0
                        for hour in receipt['rows']:
                            start = [int(x) for x in hour['inicio'].split(':')[:2]]
                            end = [int(x) for x in hour['fim'].split(':')[:2]]
                            minutes = end[0]*60+end[1]-start[0]*60-start[1]
                            if minutes <= 0:
                                raise ValueError('Intervalo de horas invalido.')
                            total += minutes
                        result['values']['hours'] = f'{total//60:02}:{total%60:02}'
                    else:
                        result['hoursError'] = 'A listagem de horas nao foi lida integralmente.'
                except Exception:
                    result['hoursError'] = 'Nao foi possivel consultar todas as horas do retroativo.'
        except AuditLookupError as error:
            result.update(error=str(error), errorCode=error.code)
        except Exception:
            result['error'] = 'Nao foi possivel abrir e conferir este trabalho. Confira o vinculo e o acesso no E-Desk.'
        rows.append(result)
    return rows


def main():
    from edesk_comentario import (carregar_request, obter_credenciais_edesk, obter_url,
                                 aguardar_login, obter_guid_da_url, instalar_monitor_requests)
    from playwright.sync_api import sync_playwright
    data = carregar_request()
    if data.get('enviar') is not False:
        raise ValueError('A conferencia aceita somente consulta.')
    credentials = obter_credenciais_edesk(data)
    rows = []
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(str(PROFILE_DIR), headless=HEADLESS, viewport=None)
        try:
            context.route('**/*', protect_read_only)
            restore_session_cookies(context)
            grid = context.pages[0] if context.pages else context.new_page()
            instalar_monitor_requests(grid)
            stage('login')
            grid.goto(obter_url(data), wait_until='domcontentloaded', timeout=60000)
            aguardar_login(grid, credenciais=credentials)
            guid = obter_guid_da_url(grid.url)
            if not guid:
                raise RuntimeError('Sessao do E-Desk nao identificada.')
            save_session_cookies(context)
            for index, target in enumerate(data['solicitacoes']):
                stage('auditing')
                try:
                    if grid.is_closed():
                        grid = context.new_page()
                    rows.extend(audit_request(context, grid, target, guid,
                        data.get('includeHours') is True, data.get('importWorkGrid') is True))
                except AuditLookupError as error:
                    rows.append({'solicitacao': target['solicitacao'], 'idTrabalho': '', 'values': {},
                        'error': str(error), 'errorCode': error.code})
                except Exception as error:
                    rows.append({'solicitacao': target['solicitacao'], 'idTrabalho': '', 'values': {},
                        'error': str(error) if data.get('importWorkGrid') is True else 'Solicitacao nao consultada. Confira o acesso, o numero e a janela do E-Desk.'})
                completed(index)
                stage('auditing')
        finally:
            context.close()
    print(json.dumps({'ok': True, 'operation': 'conferencia', 'rows': rows,
        'message': 'Conferencia concluida. Nenhum dado foi alterado.'}, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        print(json.dumps({'ok': False, 'operation': 'conferencia',
            'message': 'Nao foi possivel concluir a consulta ao E-Desk. Confira a integracao e o login.'}), flush=True)
        sys.exit(1)
