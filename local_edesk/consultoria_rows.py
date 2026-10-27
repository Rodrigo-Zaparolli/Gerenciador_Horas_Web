"""Staged structural edits of the recognized Consultorias Excel table only."""
import json
import re
from decimal import Decimal, InvalidOperation
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET
import posixpath

OPS = {'add-consultoria-row', 'delete-consultoria-row'}
INPUTS = ('B','C','D','E','F','H')
NS = {'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def split_changes(payload):
    if not isinstance(payload,list) or not 1 <= len(payload) <= 500:
        raise ValueError('Informe de 1 a 500 alteracoes.')
    normal, operations = [], []
    for change in payload:
        if not isinstance(change,dict):
            raise ValueError('Alteracao invalida.')
        if 'operation' in change:
            if change['operation'] not in OPS:
                raise ValueError('Operacao de linha invalida.')
            operations.append(change)
        else:
            normal.append(change)
    if len(operations)>100:
        raise ValueError('Altere no maximo 100 encontros por gravacao.')
    return normal,operations

def plan(before, changes, operations):
    from local_edesk.excel_editor import validated_changes
    if not before.get('consultoriaTable') or before.get('consultoriaRowOperationsVersion') not in (1,2):
        raise ValueError('Adicionar e excluir encontros exige uma tabela de Consultoria reconhecida.')
    rows={}
    for field in before['fields']:
        match=re.fullmatch(r'([B-I])([0-9]+)',field['cell'])
        if match and int(match[2])>6:
            rows.setdefault(int(match[2]),{})[match[1]]=field['value']
    for field,new in changes:
        match=re.fullmatch(r'([B-I])([0-9]+)',field['cell'])
        if not match or int(match[2]) not in rows:
            raise ValueError('Celula fora da tabela de encontros.')
        rows[int(match[2])][match[1]]=new
    deleted, added, ids=set(),[],set()
    order=list(sorted(rows))
    items=dict(rows)
    for op in operations:
        if op['operation']=='delete-consultoria-row':
            row=op.get('row')
            if type(row) is not int or row not in rows or row in deleted:
                raise ValueError('Linha de encontro invalida ou repetida.')
            deleted.add(row)
        else:
            identity=op.get('id')
            values=op.get('values',{})
            if not isinstance(identity,str) or not re.fullmatch(r'new-[0-9]{1,8}',identity) or identity in ids:
                raise ValueError('Identificador de novo encontro invalido.')
            if not isinstance(values,dict) or set(values)-set(INPUTS):
                raise ValueError('Campo de novo encontro nao permitido.')
            ids.add(identity)
            item={c:values.get(c,'Programado' if c=='H' else '') for c in INPUTS}
            fields=[{'sheet':before['worksheet'],'cell':c,'value':'Programado' if c=='H' else '',
                     'kind':'date' if c=='B' else 'time' if c in 'CDEF' else 'text',
                     'consultoriaStatus':c=='H','dateStorage':'number'} for c in INPUTS]
            validated_changes({'fields':fields,'tasks':[]},[{'sheet':before['worksheet'],'cell':c,
                'before':'Programado' if c=='H' else '','value':item[c]} for c in INPUTS])
            description=before['consultoriaDetails'].get('description','Consultoria')
            if not isinstance(description,str) or len(description)>10000 or description.lstrip().startswith(('=','+','-','@')):
                raise ValueError('A descricao do modelo nao e um texto valido para novos encontros.')
            item['I']=description
            anchor=op.get('after')
            if anchor is not None and (type(anchor) not in (int,str) or anchor not in order):
                raise ValueError('Linha de referencia para inserir abaixo invalida.')
            order.insert(order.index(anchor)+1 if anchor is not None else len(order),identity)
            items[identity]=item
            added.append(item)
    order=[r for r in order if r not in deleted]
    result=[items[r] for r in order]
    insertions=[{'position':i+1,'item':items[r]} for i,r in enumerate(order) if isinstance(r,str)]
    if len(result)>2000:
        raise ValueError('Limite de 2000 encontros excedido.')
    return {'rows':result,'deleted':sorted(deleted,reverse=True),'added':added,'insertions':insertions}

def apply(book,before,expected):
    from local_edesk.excel_editor import stored_date,stored_time
    sheet=book.Worksheets(before['worksheet'])
    table=sheet.ListObjects(before['consultoriaDetails']['tableName'])
    count=int(table.ListRows.Count)
    template_row=6+count if count else 7
    formats=[sheet.Cells(template_row,c).NumberFormat for c in range(2,11)] if count else ['dd/mm/yyyy ddd','hh:mm','hh:mm','hh:mm','hh:mm','[h]:mm','General','General','General']
    formula=sheet.Cells(template_row,7).FormulaR1C1 if count else '=(RC[-3]-RC[-4])+(RC[-1]-RC[-2])'
    if not isinstance(formula,str) or not formula.startswith('='):
        formula='=(RC[-3]-RC[-4])+(RC[-1]-RC[-2])'
    for row in expected['deleted']:
        table.ListRows(row-6).Delete()
    for insertion in expected['insertions']:
        item=insertion['item']
        new_row=table.ListRows.Add(Position=insertion['position'],AlwaysInsert=True)
        r=int(new_row.Range.Row)
        for c,fmt in zip(range(2,11),formats):
            if str(fmt).casefold() in {'general','geral'}:
                continue
            try:
                sheet.Cells(r,c).NumberFormat=fmt
            except Exception as exc:
                raise ValueError(f'Nao foi possivel aplicar o formato da coluna {c}: {fmt}') from exc
        sheet.Range(f'B{r}:F{r}').ClearContents()
        for column in INPUTS:
            val=item[column]
            val=stored_date({'dateStorage':'number'},val) if column=='B' else stored_time(val) if column in 'CDEF' else val
            sheet.Cells(r,ord(column)-64).Value2=val if val!='' else None
        sheet.Cells(r,7).FormulaR1C1=formula
        sheet.Cells(r,9).Value2=item['I']
        sheet.Cells(r,10).ClearContents()
        # ListRows normally inherits validation; explicitly retain its domain.
        validation=sheet.Cells(r,8).Validation
        try:
            inherited=int(validation.Type)==3 and all(v in str(validation.Formula1) for v in ['Programado','Realizado','Cancelado'])
        except Exception:
            inherited=False
        if not inherited:
            validation.Delete()
            settings=book.Application.International
            separator=str(settings[4]) if isinstance(settings,(tuple,list)) else str(settings(5))
            if separator not in {',',';'}:
                raise ValueError('Nao foi possivel conferir a lista de Status do Excel.')
            validation.Add(Type=3,AlertStyle=1,Operator=1,Formula1=separator.join(['Programado','Realizado','Cancelado']))
        new_row=validation=None
    if int(table.ListRows.Count)!=len(expected['rows']):
        raise ValueError('A quantidade de encontros nao foi confirmada.')
    sheet=table=None

def verify(checked,expected):
    rows={}
    for f in checked['fields']:
        match=re.fullmatch(r'([B-I])([0-9]+)',f['cell'])
        if match and int(match[2])>6:
            rows.setdefault(int(match[2]),{})[match[1]]=f
    if len(rows)!=len(expected['rows']):
        raise ValueError('Nao foi possivel conferir as linhas salvas.')
    for actual,wanted in zip([v for _,v in sorted(rows.items())],expected['rows']):
        for col in (*INPUTS,'I'):
            if actual[col]['value']!=wanted[col]:
                raise ValueError('Um valor do encontro nao foi confirmado. O original foi preservado.')
        if not actual['G']['readOnly']:
            raise ValueError('A formula do total nao foi preservada.')

def _sheets(archive):
    book=ET.fromstring(archive.read('xl/workbook.xml'))
    rels=ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
    targets={r.attrib['Id']:r.attrib['Target'] for r in rels}
    result={}
    for sheet in book.findall('s:sheets/s:sheet',NS):
        target=targets[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
        result[sheet.attrib['name']]=posixpath.normpath(target.lstrip('/') if target.startswith('/') else 'xl/'+target)
    return result

def _cells(archive,part):
    strings=[]
    if 'xl/sharedStrings.xml' in archive.namelist():
        strings=[''.join(t.text or '' for t in si.iter('{'+NS['s']+'}t')) for si in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
    root=ET.fromstring(archive.read(part))
    cells={}
    arrays=[]
    for cell in root.findall('.//s:sheetData/s:row/s:c',NS):
        f=cell.find('s:f',NS)
        if f is not None and f.attrib.get('ref'):
            arrays.append(f.attrib['ref'])
        value=cell.find('s:v',NS)
        value=value.text if value is not None else ''
        kind=cell.attrib.get('t','n')
        if kind=='s' and value: value=strings[int(value)]
        elif kind=='inlineStr': value=''.join(t.text or '' for t in cell.findall('.//s:t',NS))
        elif kind=='n' and value:
            try: value=Decimal(value)
            except InvalidOperation: pass
        cells[cell.attrib['r']]=(f is not None,value)
    return cells,arrays

def _in_arrays(address,areas):
    def pos(a):
        m=re.fullmatch(r'([A-Z]+)([0-9]+)',a.replace('$',''))
        col=0
        for c in m[1]: col=col*26+ord(c)-64
        return col,int(m[2])
    c,r=pos(address)
    for area in areas:
        a,*tail=area.split(':');b=tail[0] if tail else a
        x,y=pos(a);xx,yy=pos(b)
        if x<=c<=xx and y<=r<=yy: return True
    return False

def preserve_assets_and_check(source,target,worksheet):
    """Excel owns structural references; restore immutable VBA/control/media parts.

    Never accept loss of an existing package part or changes to input cells on
    other sheets. Formula caches and dynamic-array results may recalculate.
    """
    replacement=Path(target).with_suffix('.structure-tmp')
    try:
        with ZipFile(source) as original,ZipFile(target) as saved:
            missing=set(original.namelist())-set(saved.namelist())-{'xl/calcChain.xml'}
            if missing: raise ValueError('O Excel removeu um recurso do modelo. O original foi preservado.')
            old_sheets,new_sheets=_sheets(original),_sheets(saved)
            if set(old_sheets)!=set(new_sheets): raise ValueError('As guias do modelo mudaram.')
            for name,part in old_sheets.items():
                old,arrays=_cells(original,part);new,new_arrays=_cells(saved,new_sheets[name])
                if sum(1 for f,v in new.values() if f and v=='#REF!')>sum(1 for f,v in old.values() if f and v=='#REF!'):
                    raise ValueError('Uma referencia de formula foi quebrada. O original foi preservado.')
                if name==worksheet: continue
                if sum(f for f,v in old.values())!=sum(f for f,v in new.values()):
                    raise ValueError('Uma formula de outra guia foi removida.')
                for address,(formula,value) in old.items():
                    if formula or value=='' or _in_arrays(address,arrays+new_arrays): continue
                    actual=new.get(address,(False,''))[1]
                    equal=abs(value-actual)<=max(Decimal('0.000000001'),abs(value)*Decimal('0.00000000000001')) if isinstance(value,Decimal) and isinstance(actual,Decimal) else value==actual
                    if not equal: raise ValueError('Um dado de outra guia mudou. O original foi preservado.')
            with ZipFile(replacement,'w') as out:
                for info in saved.infolist():
                    name=info.filename
                    immutable=name in original.namelist() and (name.lower().endswith('.bin') or name.startswith(('xl/media/','xl/activeX/','xl/ctrlProps/','customUI/')))
                    out.writestr(info,original.read(name) if immutable else saved.read(name))
        import os
        os.replace(replacement,target)
    finally:
        replacement.unlink(missing_ok=True)
