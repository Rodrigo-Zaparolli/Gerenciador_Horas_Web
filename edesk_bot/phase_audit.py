"""Read adjusted dates from the request Phases tab; never change any field."""
import re
import unicodedata

def phase_key(value):
    text=unicodedata.normalize('NFD',str(value or '')).lower()
    text=''.join(c for c in text if unicodedata.category(c)!='Mn')
    text=re.sub(r'^\s*promob\s*[-:]?\s*','',text)
    text=re.sub(r'\(oh\)\s*$','',text)
    return re.sub(r'[^a-z0-9]','',text)

class PhaseReadError(ValueError):
    pass


READ_PHASES=r"""view => {
 const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
 const inputs=(owner,part)=>[...owner.querySelectorAll('input')].filter(e=>e.id.includes(part)&&e.type!=='hidden'&&visible(e));
 const names=[...view.querySelectorAll("span[id*='lblGFasNome']")].filter(visible);
 if(!names.length)throw Error('phase_rows_pending');
 return names.map(label=>{
  let owner=label.parentElement;
  while(owner&&owner!==view&&!(
    [...owner.querySelectorAll("span[id*='lblGFasNome']")].filter(visible).length===1&&
    inputs(owner,'txtGFasDtIniAj').length===1&&inputs(owner,'txtGFasDtTerAju').length===1))owner=owner.parentElement;
  if(!owner||[...owner.querySelectorAll("span[id*='lblGFasNome']")].filter(visible).length!==1||inputs(owner,'txtGFasDtIniAj').length!==1||inputs(owner,'txtGFasDtTerAju').length!==1)throw Error('phase_fields_ambiguous');
  return {name:label.textContent.trim(),start:inputs(owner,'txtGFasDtIniAj')[0].value.trim(),end:inputs(owner,'txtGFasDtTerAju')[0].value.trim()};
 });
}"""


def read_phases(page):
    view=page.locator('#cph1_rpvFasePro')
    if not view.count() or not view.first.is_visible():
        # Click the main Telerik tab anchor, not an arbitrary matching text node.
        tabs=page.locator('div.rtsLevel1 a.rtsLink').filter(
            has_text=re.compile(r'^\s*Fases\s*(?:\(\d+\))?\s*$',re.I))
        tabs=[tab for tab in tabs.all() if tab.is_visible()]
        if not tabs:
            tabs=[tab for tab in page.get_by_role('tab',name=re.compile(r'^\s*Fases\s*(?:\(\d+\))?\s*$',re.I)).all() if tab.is_visible()]
        if not tabs:
            tabs=[tab for tab in page.get_by_text(re.compile(r'^\s*Fases\s*(?:\(\d+\))?\s*$',re.I)).all() if tab.is_visible()]
        if len(tabs)!=1:raise PhaseReadError('A aba principal Fases nao foi identificada sem ambiguidade.')
        tabs[0].click(timeout=15000)
    try:
        view.wait_for(state='visible',timeout=20000)
        # A visible view may still be empty while the Telerik AJAX reply arrives.
        page.wait_for_function(r"""() => {
          const view=document.querySelector('#cph1_rpvFasePro');
          const busy=window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.();
          return !busy&&view&&[...view.querySelectorAll("span[id*='lblGFasNome']")].some(e=>e.getClientRects().length&&e.textContent.trim());
        }""",timeout=20000)
        rows=view.evaluate(READ_PHASES)
    except Exception as error:
        if 'phase_fields_ambiguous' in str(error):
            raise PhaseReadError('Os campos de datas de Fases nao possuem uma associacao unica.') from error
        raise PhaseReadError('A aba Fases abriu, mas a tabela de datas nao terminou de carregar.') from error
    keys=[phase_key(row['name']) for row in rows]
    if not all(keys) or len(set(keys))!=len(keys):raise PhaseReadError('A tabela de Fases possui nomes vazios ou repetidos.')
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
