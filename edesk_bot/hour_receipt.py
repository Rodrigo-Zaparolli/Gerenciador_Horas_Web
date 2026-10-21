"""Verify persisted retroactive rows; retry only proven missing, completed saves."""
import re
import unicodedata
from datetime import datetime


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', str(value or '').lower())
                   if not unicodedata.combining(c)).strip()


def date_value(value):
    match = re.fullmatch(r'\s*(\d{1,2}/\d{1,2}/(?:\d{4}|\d{2}))(?:\s+00:00(?::00)?)?\s*', str(value or ''))
    if not match:
        return None
    for pattern in ('%d/%m/%Y', '%d/%m/%y'):
        try:
            return datetime.strptime(match[1], pattern).strftime('%d/%m/%Y')
        except ValueError:
            pass
    return None


def time_value(value):
    match = re.fullmatch(r'\s*(\d{1,2}):(\d{2})(?::00)?\s*', str(value or ''))
    if not match or int(match[1]) > 23 or int(match[2]) > 59:
        return None
    return f'{int(match[1]):02}:{match[2]}'


def type_value(value):
    value = normalized(value)
    return {'interno': '0', 'externo': '1', 'padrao': '3', 'padrao (interno)': '4'}.get(value, value)


def presence(snapshot, hour):
    """An occupied interval with another visible type must never be inserted again."""
    target = (date_value(hour.get('data')), time_value(hour.get('inicio')), time_value(hour.get('fim')))
    if None in target:
        return 'unknown'
    matches = [row for row in snapshot.get('rows', [])
               if (date_value(row.get('data')), time_value(row.get('inicio')), time_value(row.get('fim'))) == target]
    expected_type = type_value(hour.get('tipo') or '0')
    if any(row.get('tipo') is None or type_value(row['tipo']) == expected_type for row in matches):
        return 'present'
    if matches:
        return 'occupied'
    return 'absent' if snapshot.get('complete') is True else 'unknown'


# Reads real table cells only. Inputs and the accumulated description are never
# persistence evidence. Mark only genuine paging controls, never Save controls.
GRID_SCRIPT = r'''() => {
  const norm = s => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'')
    .toLowerCase().replace(/[^a-z0-9]/g,'');
  const visible = e => !!(e && e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden');
  const aliases = {
    data:['data','datadolancamento','dataderegistro','dataregistro','dataapontamento','datadoapontamento'],
    inicio:['inicio','horainicio','horainicial','horariodeinicio','horarioinicial','entrada'],
    fim:['fim','horafim','horafinal','horariodefim','horariofinal','saida','termino'],
    tipo:['tipo','tipoderegistro','tiporegistro','tipodetempo','tipoapontamento','tipodeapontamento']
  };
  const candidates=[];
  for(const table of document.querySelectorAll('table')) {
    if(!visible(table)) continue;
    const rows=[...table.rows].filter(r=>r.closest('table')===table);
    let header=null, columns=null;
    for(const row of rows) {
      const cells=[...row.cells];
      if(!cells.length || cells.some(c=>c.querySelector('input:not([type="hidden"]),textarea,select'))) continue;
      const names=cells.map(c=>norm(c.innerText));
      const map=Object.fromEntries(Object.entries(aliases).map(([key,values])=>[key,names.findIndex(n=>values.includes(n))]));
      if(['data','inicio','fim'].every(key=>map[key]>=0)) {header=row;columns=map;break;}
    }
    if(!header) continue;
    const result={rows:[],complete:true,grid:table.id||'',pager:false,index:null,next:null,first:null};
    const scope=table.closest('.RadGrid')||table;
    const pagerRows=rows.filter(r=>[...r.cells].some(c=>c.colSpan>1) &&
      (r.querySelector('a[href*="Page$"],.rgPageNext,.rgCurrentPage') || /pager|pagin/i.test(r.className)));
    const pagers=[...scope.querySelectorAll('.rgPager,.pager,.gridPager') ,...pagerRows];
    const pagerElements=[...new Set(pagers.flatMap(r=>[...r.querySelectorAll('a,input,button,span')]))];
    const links=pagerElements.filter(visible).filter(e=>e.matches('a,input,button'));
    const current=[...new Set(pagerElements.filter(e=>visible(e) &&
      ((e.tagName==='SPAN' && !e.closest('a')) || e.matches('.rgCurrentPage')) && /^\d+$/.test(e.textContent.trim()))
      .map(e=>Number(e.textContent.trim())))];
    if(current.length===1)result.index=current[0];
    const commands=links.map(e=>{
      const href=e.getAttribute('href')||'';
      const arg=(href.match(/['"]Page\$(First|Next|Last|Previous|\d+)['"]/i)||[])[1];
      const disabled=e.matches('[disabled],[aria-disabled="true"],.aspNetDisabled') || /disabled/i.test(e.className);
      return {e,arg,disabled};
    });
    result.pager=pagers.length>0 || commands.some(c=>c.arg);
    const first=commands.find(c=>!c.disabled && (c.arg==='First'||c.arg==='1'));
    const next=commands.find(c=>!c.disabled && c.arg==='Next') || commands.filter(c=>!c.disabled && /^\d+$/.test(c.arg||'') && result.index && Number(c.arg)>result.index)
      .sort((a,b)=>Number(a.arg)-Number(b.arg))[0];
    for(const e of document.querySelectorAll('[data-gh-hours-page]'))e.removeAttribute('data-gh-hours-page');
    if(first){first.e.setAttribute('data-gh-hours-page','first');result.first='[data-gh-hours-page="first"]';}
    if(next){next.e.setAttribute('data-gh-hours-page','next');result.next='[data-gh-hours-page="next"]';}
    // Unknown pager commands cannot prove that this is the final page.
    if(result.pager && (!result.index || links.some(e=>!commands.some(c=>c.e===e&&c.arg)&&!e.matches('.rgCurrentPage'))))result.complete=false;
    if([...scope.querySelectorAll('.rgFilterRow input:not([type="hidden"]):not([type="checkbox"])')].some(e=>(e.value||'').trim()))result.complete=false;
    for(const row of rows) {
      if(row===header || row.querySelector('th') || pagerRows.includes(row))continue;
      const cells=[...row.cells];
      if(!cells.length)continue;
      if(cells.length<=Math.max(columns.data,columns.inicio,columns.fim)) {
        if(!/nenhum|naoha|naoexist|semregistro|semapontamento|semitens|norecord|noitem|nodata/.test(norm(cells.map(c=>c.innerText).join(' '))))result.complete=false;
        continue;
      }
      if(cells.some(c=>c.querySelector('input:not([type="hidden"]),textarea,select'))) {result.complete=false;continue;}
      result.rows.push({data:cells[columns.data].innerText.trim(),inicio:cells[columns.inicio].innerText.trim(),
        fim:cells[columns.fim].innerText.trim(),tipo:columns.tipo>=0?cells[columns.tipo]?.innerText.trim():null});
    }
    const total=Number(table.getAttribute('aria-rowcount'));
    if(total>result.rows.length+1 && !result.pager)result.complete=false;
    candidates.push(result);
  }
  return candidates.length===1 ? candidates[0] : {complete:false,rows:[],reason:'A listagem de horas nao foi identificada de forma unica.'};
}'''


def read_hours(page, max_pages=100):
    """Read all reachable ASP.NET grid pages; fail closed for unknown pagination."""
    collected, visited = [], set()
    for step in range(max_pages):
        page.wait_for_function('''() => document.readyState !== 'loading' &&
          !(window.Sys?.WebForms?.PageRequestManager?.getInstance()?.get_isInAsyncPostBack())''', timeout=15000)
        data = page.evaluate(GRID_SCRIPT)
        if step == 0 and (data.get('index') or 1) > 1:
            if not data.get('first'):
                return {**data, 'complete': False}
            page.locator(data['first']).click(timeout=10000)
            page.wait_for_timeout(200)
            data = page.evaluate(GRID_SCRIPT)
            if data.get('index') != 1:
                return {**data, 'complete': False}
        identity = (data.get('grid'), data.get('index'), repr(data.get('rows')))
        if identity in visited:
            return {'rows': collected, 'complete': False, 'reason': 'A paginacao nao avancou.'}
        visited.add(identity)
        for row in data.get('rows', []):
            if not all((date_value(row.get('data')), time_value(row.get('inicio')), time_value(row.get('fim')))):
                data['complete'] = False
        collected.extend(data.get('rows', []))
        if data.get('complete') is not True:
            return {'rows': collected, 'complete': False, 'reason': data.get('reason', 'Listagem incompleta ou filtrada.')}
        if not data.get('next'):
            return {'rows': collected, 'complete': True}
        page.locator(data['next']).click(timeout=10000)
        page.wait_for_timeout(200)
    return {'rows': collected, 'complete': False, 'reason': 'Limite de paginas atingido.'}


def deliver_hours(hours, read_fresh, submit, emit, stage=lambda _: None):
    """One initial pass and at most one safe retry, always followed by a new read.

    submit returns completed/not_submitted/unknown. An unacknowledged POST is
    never automatically repeated, even if a later read does not show its row.
    """
    outcomes, retried, errors = {}, set(), []

    def inspect():
        stage('checking')
        try:
            return read_fresh()
        except Exception as error:
            errors.append(str(error))
            return {'rows': [], 'complete': False}

    def send(index, retry=False):
        if retry:
            stage('retrying')
            retried.add(index)
        try:
            outcome = submit(hours[index], index + 1, retry)
            outcomes[index] = outcome if outcome in {'completed', 'not_submitted'} else 'unknown'
        except Exception as error:
            errors.append(str(error))
            outcomes[index] = 'unknown'

    snapshot = inspect()
    for index, hour in enumerate(hours):
        state = presence(snapshot, hour)
        if state == 'absent':
            send(index)
            snapshot = inspect()
        elif state not in {'present'}:
            errors.append('Listagem incompleta ou intervalo ocupado por outro tipo de registro.')

    snapshot = inspect()
    for index, hour in enumerate(hours):
        if presence(snapshot, hour) == 'absent' and outcomes.get(index, 'not_submitted') in {'completed', 'not_submitted'}:
            # A second independent GET catches late/previous successful commits.
            snapshot = inspect()
            if presence(snapshot, hour) == 'absent':
                send(index, retry=True)
                snapshot = inspect()

    snapshot = inspect()
    confirmed, missing, uncertain = [], [], []
    for index, hour in enumerate(hours):
        state = presence(snapshot, hour)
        if state == 'present':
            confirmed.append(index)
            emit(hour, 'confirmed')
        elif state == 'absent' and outcomes.get(index) in {'completed', 'not_submitted'}:
            missing.append(index)
            emit(hour, 'not_submitted')
        else:
            uncertain.append(index)
    ok = len(confirmed) == len(hours)
    message = (f'{len(confirmed)} hora(s) conferidas no E-Desk. Nenhuma hora pendente. '
               'Cadastro finalizado com sucesso.' if ok else
               f'{len(confirmed)} de {len(hours)} hora(s) confirmadas; {len(missing)} nao cadastradas e '
               f'{len(uncertain)} sem comprovacao. Somente ausencias comprovadas foram tentadas novamente; '
               'os demais envios nao foram repetidos para evitar duplicidade.')
    return {'operation': 'horas', 'ok': ok, 'total': len(hours), 'verified': len(confirmed),
            'retried': len(retried), 'missing': len(missing), 'uncertain': len(uncertain),
            'message': message, 'details': errors[-3:]}
