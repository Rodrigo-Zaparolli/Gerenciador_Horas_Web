"""Read-only work inspection. Never fill a work field or invoke Save."""
import json
import re
import sys
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
    percentage:['%realizado','percentualrealizado','percentualdeconclusao']};
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


def show_works(page):
    panel = page.locator('#cph1_rpvTrabalhos')
    if not panel.count() or not panel.first.is_visible():
        tabs = [tab for tab in page.get_by_text(re.compile(r'^Trabalhos\s*(?:\(\d+\))?$')).all() if tab.is_visible()]
        if len(tabs) != 1:
            raise RuntimeError('Aba Trabalhos ausente ou ambigua.')
        tabs[0].click(timeout=15000)
    page.locator('#cph1_gvwTra').wait_for(state='visible', timeout=15000)
    page.wait_for_function("() => !window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()")


def work_numbers(page):
    show_works(page)
    # Unknown pagination must never be reported as a complete request.
    table = page.locator('#cph1_gvwTra')
    if table.locator('a[href*="Page$"],.rgPager').count():
        raise RuntimeError('Solicitacao paginada: selecione um projeto com os numeros dos trabalhos cadastrados no app.')
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


def audit_request(context, grid, target, guid, include_hours=False):
    from edesk_comentario import (acessar_minha_grid, abrir_solicitacao_para_comentario,
                                  localizar_solicitacao_validada)
    from edesk_horas import abrir_trabalho_na_solicitacao, validar_tela_trabalho, abrir_trabalho_retroativo, extrair_dados_url
    from hour_receipt import read_hours
    solicitation = target['solicitacao']
    acessar_minha_grid(grid, guid)
    page, row, opened = localizar_solicitacao_validada(grid, context, solicitation)
    request_page = abrir_solicitacao_para_comentario(page, context, row, solicitation, opened)
    request_url = request_page.url
    numbers = target.get('trabalhos') or work_numbers(request_page)
    if not numbers:
        raise RuntimeError('Nenhum numero de trabalho foi identificado na solicitacao.')
    rows = []
    for number in numbers:
        result = {'solicitacao': solicitation, 'idTrabalho': str(number), 'values': {}}
        try:
            if request_page.is_closed():
                request_page = context.new_page()
            request_page.goto(request_url, wait_until='domcontentloaded', timeout=30000)
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
                    rows.extend(audit_request(context, grid, target, guid, data.get('includeHours') is True))
                except Exception:
                    rows.append({'solicitacao': target['solicitacao'], 'idTrabalho': '', 'values': {},
                        'error': 'Solicitacao nao consultada. Confira o acesso, o numero e a janela do E-Desk.'})
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
