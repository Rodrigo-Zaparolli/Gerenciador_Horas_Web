"""Read adjusted dates from the request Phases tab; never change any field."""
import re
import unicodedata

def phase_key(value):
    text=unicodedata.normalize('NFD',str(value or '')).lower()
    text=''.join(c for c in text if unicodedata.category(c)!='Mn')
    text=re.sub(r'^\s*promob\s*[-:]?\s*','',text)
    text=re.sub(r'\(oh\)\s*$','',text)
    return re.sub(r'[^a-z0-9]','',text)

READ_PHASES=r"""view => {
 const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
 const names=[...view.querySelectorAll("span[id*='lblGFasNome']")].filter(visible);
 if(!names.length)throw Error('Nenhuma fase reconhecida.');
 return names.map(label=>{
  let owner=label.parentElement;
  while(owner&&owner!==view&&!(owner.querySelectorAll("span[id*='lblGFasNome']").length===1&&owner.querySelectorAll("input[id*='txtGFasDtIniAj']").length===1&&owner.querySelectorAll("input[id*='txtGFasDtTerAju']").length===1))owner=owner.parentElement;
  if(!owner||owner===view)throw Error('Campos de fase sem associacao unica.');
  return {name:label.textContent.trim(),start:owner.querySelector("input[id*='txtGFasDtIniAj']").value.trim(),end:owner.querySelector("input[id*='txtGFasDtTerAju']").value.trim()};
 });
}"""

def read_phases(page):
    view=page.locator('#cph1_rpvFasePro')
    if not view.count() or not view.first.is_visible():
        tabs=[t for t in page.get_by_text(re.compile(r'^Fases\s*(?:\(\d+\))?$')).all() if t.is_visible()]
        if len(tabs)!=1:raise ValueError('A aba Fases nao foi identificada sem ambiguidade.')
        tabs[0].click(timeout=15000)
    view.wait_for(state='visible',timeout=15000)
    page.wait_for_function("() => !window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()",timeout=15000)
    rows=view.evaluate(READ_PHASES)
    keys=[phase_key(row['name']) for row in rows]
    if not all(keys) or len(set(keys))!=len(keys):raise ValueError('Nomes de fases vazios ou repetidos.')
    return {key:row for key,row in zip(keys,rows)}

def phase_dates(phases,work):
    key=phase_key(work.get('phase') or work.get('name'))
    if key not in phases:raise ValueError('Nao foi encontrada uma fase unica para este trabalho.')
    row=phases[key]
    return {'start':row['start'],'end':row['end'],'phaseName':row['name']}

def summarize_work(values):
    status=phase_key(values.get('status'))
    if status in {'concluido','concluida','finalizado','finalizada','encerrado','encerrada','trabfim'}:
        values['completed']='Sim'
    elif status in {'emandamento','andamento','parado','parada','pausado','pausada','naoiniciado','naoiniciada','aberto','aberta','trabexe','trabstop','inipro','exepro'}:
        values['completed']='Nao'
    def minutes(value):
        if not isinstance(value,str) or not re.fullmatch(r'\d{1,5}:[0-5]\d',value):return None
        h,m=map(int,value.split(':'));return h*60+m
    planned,done=minutes(values.get('estimatedHours')),minutes(values.get('hours'))
    if planned is not None and done is not None:
        remaining=max(0,planned-done);extra=max(0,done-planned)
        values['remainingHours']=f'{remaining//60:02}:{remaining%60:02}'
        values['overrunHours']=f'{extra//60:02}:{extra%60:02}'
