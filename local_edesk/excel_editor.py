"""Pilot editor: mapped cells only, Excel COM, staged writes and file revision checks."""
from contextlib import contextmanager
from datetime import datetime, timedelta
import hashlib
import json
import logging
import math
import os
from pathlib import Path
import shutil
import tempfile
import threading
import uuid
from zipfile import ZipFile
from types import SimpleNamespace
import re
import unicodedata
import posixpath
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

lock = threading.Lock()
BASE = datetime(1899, 12, 30)


def allowed(user):
    # Only verified Firebase claims reach this check. Resource UID is checked
    # independently by local_files.execute before any filesystem operation.
    return isinstance(user.get('sub'), str) and bool(user['sub'].strip())


def revision(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class _ExcelHandle:
    """Detach caller-held proxies before COM is uninitialized."""
    def __init__(self, target):
        self.target = target

    def __getattr__(self, name):
        if self.target is None:
            raise RuntimeError('A sessão de leitura do Excel já foi encerrada.')
        return getattr(self.target, name)


@contextmanager
def workbook(path, writable=False):
    import pythoncom
    import win32com.client
    pythoncom.CoInitialize()
    app = book = None
    handles = []
    try:
        app = win32com.client.DispatchEx('Excel.Application')
        app.Visible = False
        app.AutomationSecurity = 3  # Never execute workbook macros.
        app.EnableEvents = False
        app.DisplayAlerts = False
        app.AskToUpdateLinks = False
        book = app.Workbooks.Open(str(Path(path).resolve()), UpdateLinks=0,
                                 ReadOnly=not writable, IgnoreReadOnlyRecommended=True)
        if writable and book.ReadOnly:
            raise ValueError('A cópia da planilha está bloqueada para edição.')
        handles = [_ExcelHandle(app), _ExcelHandle(book)]
        yield tuple(handles)
    finally:
        for handle in handles:
            handle.target = None
        try:
            if book is not None:
                book.Close(SaveChanges=False)
        finally:
            try:
                if app is not None:
                    app.Quit()
            finally:
                book = None
                app = None
                pythoncom.CoUninitialize()


def value(cell, kind):
    raw = cell.Value2
    if kind == 'date':
        if raw is None or raw == '' or raw == 0:
            return ''
        if isinstance(raw, (int, float)) and not isinstance(raw, bool):
            try:
                return (BASE + timedelta(days=float(raw))).strftime('%Y-%m-%d')
            except (ValueError, OverflowError):
                return str(raw)
        text = str(raw).strip()
        for pattern in ('%Y-%m-%d', '%d/%m/%Y', '%d/%m/%y'):
            try:
                return datetime.strptime(text, pattern).strftime('%Y-%m-%d')
            except ValueError:
                pass
        # Templates may contain instructions/placeholders instead of a date.
        # Show the original text without rewriting it or failing the whole read.
        return text
    if kind == 'time':
        if raw is None or raw == '':
            return ''
        if isinstance(raw, str):
            return raw.strip()
        minutes = round(float(raw or 0) * 1440)
        return f'{minutes // 60:02}:{minutes % 60:02}'
    if kind == 'percent':
        return float(raw or 0)
    if raw is None:
        return ''
    return str(int(raw)) if isinstance(raw, float) and raw.is_integer() else str(raw)


class SheetSnapshot:
    """Read cells in two COM calls instead of thousands of RPC calls."""
    def __init__(self, sheet):
        self.Name = sheet.Name
        self.source = sheet
        self.values = sheet.Range('A1:AH500').Value2
        self.formulas = sheet.Range('A1:AH500').Formula
        self.ListObjects = sheet.ListObjects

    def Cells(self, row, column):
        formula = self.formulas[row - 1][column - 1]
        return SimpleNamespace(Value2=self.values[row - 1][column - 1],
                               HasFormula=isinstance(formula, str) and formula.startswith('='))

    def Range(self, address):
        match = re.fullmatch(r'([A-Z]+)(\d+)', address)
        column = 0
        for character in match[1]:
            column = column * 26 + ord(character) - 64
        return self.Cells(int(match[2]), column)


def checklist_sheet(service_type, sheet_names=None):
    if sheet_names is not None:
        if not isinstance(sheet_names, dict):
            raise ValueError('Configuração de abas inválida.')
        for key, name in sheet_names.items():
            if key not in {'entry', 'checklist'} or not isinstance(name, str) or not name.strip() or len(name) > 31 or re.search(r'[\\/*?:\[\]\r\n]', name):
                raise ValueError('Informe um nome de aba válido, com até 31 caracteres.')
        if sheet_names.get('entry', '').casefold() == (sheet_names.get('checklist') or checklist_sheet(service_type)).casefold():
            raise ValueError('Selecione abas diferentes para informações de entrada e checklist.')
        if sheet_names.get('checklist'):
            return sheet_names['checklist']
    value = str(service_type or '').strip().casefold()
    return 'Maker Checklist-Processo' if 'professional' in value or 'profissional' in value else 'Checklist-Processo'


def checklist_table(checklist):
    matches = []
    for table in checklist.ListObjects:
        row = int(table.Range.Row)
        if (int(table.Range.Column) == 3 and int(table.Range.Columns.Count) >= 25
                and str(checklist.Cells(row, 5).Value2).strip() == '% Status Tarefas'
                and str(checklist.Cells(row, 6).Value2).strip() == 'Tarefas'):
            matches.append((row, int(table.Range.Row + table.Range.Rows.Count - 1)))
    if len(matches) != 1 or matches[0][1] > 500:
        raise ValueError('Não foi possível identificar a tabela de tarefas do checklist. Nenhuma célula será alterada.')
    return matches[0]


def snapshot(book, service_type=None, sheet_names=None):
    name = checklist_sheet(service_type, sheet_names)
    entry_name = (sheet_names or {}).get('entry', 'Informações de entrada')
    try:
        entry = SheetSnapshot(book.Worksheets(entry_name))
        checklist = SheetSnapshot(book.Worksheets(name))
    except Exception as error:
        raise ValueError(f'Confira as abas {entry_name} e {name}. Use Configurar abas no editor para selecionar os nomes existentes neste arquivo.') from error
    first, last = checklist_table(checklist)
    fields, tasks = [], []

    def add(sheet, address, label, group, kind='text'):
        cell = sheet.Range(address)
        field = {'sheet': sheet.Name, 'cell': address, 'label': label,
                       'group': group, 'kind': kind, 'value': value(cell, kind),
                       'readOnly': bool(cell.HasFormula)}
        if kind == 'date':
            field['dateStorage'] = 'text' if isinstance(cell.Value2, str) or sheet.source.Range(address).NumberFormat == '@' else 'number'
        fields.append(field)

    labels = {'ID da solicitação no E-Desk', 'Tipo Projeto', 'Assinatura da proposta',
              'Início do projeto pela Consultoria', 'Encerramento do projeto',
              'Nome do sistema', 'Nome resumido do sistema', 'ID da Biblioteca',
              'NS para instalação', 'Versão / Revisão', 'Senha do Configurador de Dimensões',
              'Senha dos Orçamentos', 'Senha das Margens', 'Materiais da Implantação',
              'Sistema do cliente', 'ID'}
    found = set()
    for row in range(2, 54):
        label = str(entry.Cells(row, 2).Value2 or '').strip()
        if label in labels:
            if label in found:
                raise ValueError('O modelo possui campos duplicados. Confira a planilha.')
            found.add(label)
            kind = 'date' if label in {'Assinatura da proposta', 'Início do projeto pela Consultoria', 'Encerramento do projeto'} else 'text'
            add(entry, f'C{row}', label, 'Datas' if kind == 'date' else 'Projeto e sistema', kind)
    if not {'ID da solicitação no E-Desk', 'Nome do sistema'} <= found:
        raise ValueError('A aba de entrada não corresponde ao modelo esperado.')
    for row in range(5, 18):
        if str(entry.Cells(row, 2).Value2 or '') in {'Sim', 'Não'}:
            add(entry, f'B{row}', str(entry.Cells(row, 3).Value2 or ''), 'Produtos e serviços', 'yesno')
    # Locate roles/labels rather than relying on row numbers shifted by templates.
    contact_mode = False
    role = ''
    for row in range(17, 54):
        label = str(entry.Cells(row, 5).Value2 or '').strip()
        if label in {'EQUIPE CLIENTE', 'EQUIPE CYNCLY'}:
            contact_mode = True
            role = 'Cliente' if label == 'EQUIPE CLIENTE' else 'Equipe Cyncly'
            continue
        if label in {'CLIENTE', 'CYNCLY', 'INFORMAÇÕES COMERCIAIS', 'ACESSO AO PRICES'}:
            contact_mode = False
            continue
        if not label:
            continue
        if contact_mode:
            columns = [('F', 'Nome'), ('G', 'E-mail'), ('H', 'Telefone')]
            if role == 'Cliente':
                columns.append(('I', 'CPF'))
            for col, suffix in columns:
                add(entry, f'{col}{row}', f'{label} — {suffix}', role)
        else:
            add(entry, f'F{row}', label, 'Cadastro do cliente e acessos')
            other = str(entry.Cells(row, 7).Value2 or '').strip()
            if other:
                add(entry, f'H{row}', other, 'Cadastro do cliente e acessos')
    tasks.extend(checklist_tasks(checklist, first, last))
    timeline, timeline_sheet = timeline_fields(book)
    fields.extend(timeline)
    progress = checklist.Range(f'T{first - 1}').Value2
    formulas = [(sheet.Name, row, column, formula)
                for sheet in [entry, checklist] + ([timeline_sheet] if timeline_sheet is not None else [])
                for row, values in enumerate(sheet.formulas, 1)
                for column, formula in enumerate(values, 1)
                if isinstance(formula, str) and formula.startswith('=')]
    return {'fields': fields, 'tasks': tasks,
            'entrySheet': entry.Name,
            'checklistSheet': checklist.Name,
            'formulaFingerprint': hashlib.sha256(json.dumps(formulas).encode()).hexdigest(),
            'formulaCount': len(formulas),
            'progress': float(progress) if isinstance(progress, (int, float)) and 0 <= progress <= 1 else None}


def timeline_fields(book):
    name = 'Implantação - Linha do Tempo'
    try:
        source = book.Worksheets(name)
    except Exception:
        return [], None
    sheet = SheetSnapshot(source)
    tables = [table for table in sheet.ListObjects if str(table.Name) == 'DetalhesProjeto']
    if len(tables) != 1:
        return [], sheet
    table = tables[0].Range
    first, last = int(table.Row), int(table.Row + table.Rows.Count - 1)
    if int(table.Column) != 1 or last > 500 or str(sheet.Cells(first, 3).Value2).strip() != 'Data':
        return [], sheet
    fields = []
    for row in range(first + 1, last + 1):
        label = str(sheet.Cells(row, 2).Value2 or '').strip()
        if not label:
            continue
        cell = sheet.Cells(row, 3)
        fields.append({'sheet': name, 'cell': f'C{row}', 'kind': 'date',
            'label': label, 'group': 'Linha do tempo', 'timeline': True,
            'value': value(cell, 'date'), 'readOnly': bool(cell.HasFormula),
            'dateStorage': 'text' if isinstance(cell.Value2, str) or source.Range(f'C{row}').NumberFormat == '@' else 'number'})
    return fields, sheet


def checklist_tasks(checklist, first, last):
    tasks = []
    block = block_id = previous_group = ''
    for row in range(first + 1, last + 1):
        description = str(checklist.Cells(row, 6).Value2 or '').strip()
        group = str(checklist.Cells(row, 4).Value2 or '').strip()
        if group != previous_group:
            block = block_id = ''
            previous_group = group
        cell = checklist.Cells(row, 5)
        raw = cell.Value2
        if description and not cell.HasFormula and (raw is None or isinstance(raw, str) and not raw.strip()):
            block, block_id = description, f'{checklist.Name}!F{row}'
        if not description or cell.HasFormula or not isinstance(raw, (int, float)):
            continue
        if isinstance(raw, bool) or not 0 <= raw <= 1:
            continue
        estimate = checklist.Cells(row, 8).Value2
        minutes = round(float(estimate) * 1440) if isinstance(estimate, (int, float)) else 0
        tasks.append({'sheet': checklist.Name, 'cell': f'E{row}', 'kind': 'percent',
                      'value': float(raw), 'label': description,
                      'group': group, 'block': block, 'blockId': block_id,
                      'estimated': f'{minutes // 60:02}:{minutes % 60:02}',
                      'note': str(checklist.Cells(row, 10).Value2 or '')})
    return tasks


def status_preview(book, service_type, sheet_names=None):
    name = checklist_sheet(service_type, sheet_names)
    sheet = SheetSnapshot(book.Worksheets(name))
    first, last = checklist_table(sheet)
    def number(value):
        return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) and -1e-9 <= value <= 1 + 1e-9 else None
    progress = {}
    tasks = checklist_tasks(sheet, first, last)
    for task in tasks:
        row = int(task['cell'][1:])
        raw = sheet.Cells(row, 17).Value2  # % Tar. no Trab.: actual Excel coefficient.
        weight = 0.0 if raw == '-' else number(raw)
        if weight is not None:
            progress[f"{task['sheet']}!{task['cell']}"] = {'weight': weight, 'value': task['value']}
    # Column C can contain a sub-work total. Aggregate the complete stage
    # from Excel's Q coefficients, never from the first displayed block.
    aggregates = {}
    for task in tasks:
        aggregates.setdefault(task.get('group', ''), []).append(task)
    def complete_stage(row):
        members = aggregates.get(row['label'], [])
        if members:
            row['percentage'] = None
        items = [progress.get(f"{t['sheet']}!{t['cell']}") for t in members]
        if items and all(item is not None for item in items):
            weight = sum(item['weight'] for item in items)
            if abs(weight - 1) <= 1e-6:
                row['percentage'] = min(1.0, max(0.0, sum(
                    item['weight'] * item['value'] for item in items)))
        return row
    total = number(sheet.Cells(first - 1, 5).Value2)
    rows = []
    if first >= 16:
        # This is the same Status Projeto block used by the comment preview.
        dados = book.Worksheets('Dados')
        header = str(dados.Range('AG5').Value2 or '').strip()
        formula = str(dados.Range('AH5').Formula or '')
        reference = "'" + name.replace("'", "''") + "'!"
        if header == 'Status Projeto' and (reference.casefold() in formula.casefold() or re.search(r"(?<![\w '\-])" + re.escape(name) + r'!', formula, re.I)):
            total = number(dados.Range('AH5').Value2)
            for row in range(7, 12):
                label = str(dados.Cells(row, 33).Value2 or '').strip()
                if not label:
                    continue
                rows.append({'label': label, 'percentage': number(dados.Cells(row, 34).Value2),
                    'start': value(dados.Cells(row, 35), 'date'),
                    'end': value(dados.Cells(row, 36), 'date'),
                    'weight': number(dados.Cells(row, 37).Value2),
                    'planned': number(dados.Cells(row, 38).Value2)})
            return {'total': total, 'rows': [complete_stage(row) for row in rows], 'source': 'Dados!AG5:AL11', 'taskProgress': progress}
    # Maker has no Status Projeto block linked to its checklist in the template.
    # Read its own calculated stage cells, never the Enterprise summary.
    for row in range(first + 1, last + 1):
        label = str(sheet.Cells(row, 4).Value2 or '').strip()
        percentage = number(sheet.Cells(row, 3).Value2)
        if label and percentage is not None and not any(r['label'] == label for r in rows):
            weights = [sheet.Cells(r, 18).Value2 for r in range(first + 1, last + 1)
                if str(sheet.Cells(r, 4).Value2 or '').strip() == label]
            weight = sum(float(v) for v in weights if isinstance(v, (int, float)) and not isinstance(v, bool))
            rows.append({'label': label, 'percentage': percentage, 'weight': number(weight)})
    return {'total': total, 'rows': [complete_stage(row) for row in rows], 'source': sheet.Name, 'taskProgress': progress}


def validated_changes(current, changes):
    if not isinstance(changes, list) or not 1 <= len(changes) <= 500:
        raise ValueError('Informe de 1 a 500 alterações.')
    mapped = {(x['sheet'], x['cell']): x for x in current['fields'] + current['tasks'] if not x.get('readOnly')}
    result, seen = [], set()
    for change in changes:
        if not isinstance(change, dict):
            raise ValueError('Alteração inválida.')
        key = (change.get('sheet'), change.get('cell'))
        if key not in mapped or key in seen:
            raise ValueError('Campo não permitido ou repetido na alteração.')
        seen.add(key)
        field = mapped[key]
        if change.get('before') != field['value']:
            raise ValueError('A planilha mudou desde a leitura. Recarregue antes de salvar.')
        new = change.get('value')
        kind = field['kind']
        if field.get('generic') and kind == 'text' and field['value'] == '' and isinstance(new, (int, float)) and not isinstance(new, bool):
            kind = 'number'
            field = {**field, 'kind': kind}
        if field.get('consultoriaStatus'):
            if not isinstance(new, str) or new not in {'Programado', 'Realizado', 'Cancelado'}:
                raise ValueError('Selecione Programado, Realizado ou Cancelado.')
        elif field.get('scheduleStatus'):
            if isinstance(new, str) and new in {'Programado', 'Cancelado', 'Reprogramado', ''}:
                field = {**field, 'kind': 'text'}
            elif isinstance(new, bool) or not isinstance(new, (int, float)) or not math.isfinite(new) or not 0 <= new <= 1:
                raise ValueError('Status invalido. Use percentual de 0 a 100, Programado ou Cancelado.')
            else:
                field = {**field, 'kind': 'number'}
        elif kind == 'number':
            if isinstance(new, bool) or not isinstance(new, (int, float)) or not math.isfinite(new):
                raise ValueError('Numero invalido.')
            if field.get('percent') and not 0 <= new <= 1:
                raise ValueError('Use um percentual de 0 a 100.')
        elif kind == 'percent':
            if isinstance(new, bool) or not isinstance(new, (int, float)) or not math.isfinite(new) or new not in {0, .25, .5, .75, 1}:
                raise ValueError('Use 0%, 25%, 50%, 75% ou 100%.')
        elif not isinstance(new, str) or len(new) > 10000:
            raise ValueError('Texto inválido ou muito longo.')
        elif kind == 'yesno' and new not in {'Sim', 'Não'}:
            raise ValueError('Selecione Sim ou Não.')
        elif kind == 'time':
            if new and not re.fullmatch(r'[0-9]{1,4}:[0-5][0-9]', new):
                raise ValueError('Horario invalido. Use HH:mm.')
        elif kind == 'date' and new:
            try:
                datetime.strptime(new, '%Y-%m-%d')
            except ValueError:
                raise ValueError('Data inválida.') from None
        # Do not accept formulas as field input.
        elif new.lstrip().startswith(('=', '+', '-', '@')):
            raise ValueError('Este campo não aceita fórmulas. Para telefone, use apenas números e pontuação.')
        result.append((field, new))
    return result


def stored_time(text):
    if not text:
        return None
    hours, minutes = map(int, text.split(':'))
    return (hours * 60 + minutes) / 1440


def stored_date(field, new):
    if not new:
        return '' if field.get('dateStorage') == 'text' else None
    date = datetime.strptime(new, '%Y-%m-%d')
    return date.strftime('%d/%m/%Y') if field.get('dateStorage') == 'text' else (date - BASE).days


def vba(path):
    with ZipFile(path) as archive:
        return archive.read('xl/vbaProject.bin') if 'xl/vbaProject.bin' in archive.namelist() else None


def check_assets(source, target):
    with ZipFile(source) as original, ZipFile(target) as saved:
        for name in original.namelist():
            if name.startswith(('xl/media/', 'xl/ctrlProps/', 'xl/activeX/')):
                if name not in saved.namelist():
                    raise ValueError('Um controle ou imagem do modelo foi removido. O original foi preservado.')
                if name.startswith('xl/media/') and original.read(name) != saved.read(name):
                    raise ValueError('Uma imagem do modelo mudou. O original foi preservado.')


def preserve_package(source, target, changes):
    """Keep the original package; patch only edited cells and calculated caches.

    Excel may rewrite VBA caches and recompress images on Save. Using its saved
    copy only as a source of recalculated values avoids changing those assets.
    """
    ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    def sheets(archive):
        relationships = {r.attrib['Id']: r.attrib['Target'] for r in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
        return {s.attrib['name']: posixpath.normpath('xl/' + relationships[s.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']].lstrip('/').removeprefix('xl/'))
                for s in ET.fromstring(archive.read('xl/workbook.xml')).findall('s:sheets/s:sheet', ns)}

    def patched_cell(raw, address, kind, new):
        pattern = r'<c\b[^>]*\br="' + re.escape(address) + r'"[^>]*?(?:/>|>.*?</c>)'
        matches = list(re.finditer(pattern, raw, re.S))
        if len(matches) != 1:
            raise ValueError('Uma célula editada não foi localizada de forma única no arquivo original.')
        old = matches[0].group()
        opening = old[:old.index('>') + 1].replace('/>', '>')
        opening = re.sub(r'\s+t="[^"]*"', '', opening)
        if kind:
            opening = opening[:-1] + f' t="{kind}">'
        inside = '' if old.endswith('/>') else old[old.index('>') + 1:-4]
        inside = re.sub(r'<v\b[^>]*?(?:/>|>.*?</v>)|<is\b[^>]*?(?:/>|>.*?</is>)', '', inside, flags=re.S)
        if new is not None:
            encoded = escape(str(new))
            inside += f'<is><t xml:space="preserve">{encoded}</t></is>' if kind == 'inlineStr' else f'<v>{encoded}</v>'
        return raw[:matches[0].start()] + opening + inside + '</c>' + raw[matches[0].end():]

    replacement = target.with_suffix(target.suffix + '.vba-tmp')
    try:
        with ZipFile(source) as original, ZipFile(target) as saved:
            original_sheets, saved_sheets = sheets(original), sheets(saved)
            strings = []
            if 'xl/sharedStrings.xml' in saved.namelist():
                strings = [''.join(node.itertext()) for node in ET.fromstring(saved.read('xl/sharedStrings.xml'))]
            updates = {}
            for name, part in original_sheets.items():
                raw = original.read(part).decode('utf-8')
                old_root = ET.fromstring(raw)
                cell_updates = {}
                calculated = {c.attrib['r']: c for c in ET.fromstring(saved.read(saved_sheets[name])).findall('.//s:sheetData/s:row/s:c', ns)}
                # Dynamic-array children have cached results without their own
                # formula node. Preserve the original formulas/metadata while
                # refreshing all cached values inside their original spill area.
                def position(address):
                    match = re.fullmatch(r'([A-Z]+)([1-9][0-9]*)', address)
                    if not match:
                        raise ValueError('Referencia de matriz invalida.')
                    col = 0
                    for letter in match[1]:
                        col = col * 26 + ord(letter) - 64
                    return col, int(match[2])
                array_areas = []
                for formula in old_root.findall('.//s:sheetData/s:row/s:c/s:f', ns):
                    ref = formula.attrib.get('ref')
                    if formula.attrib.get('t') == 'array' and ref:
                        parts = ref.replace('$', '').split(':')
                        array_areas.append((position(parts[0]), position(parts[-1])))
                for cell in old_root.findall('.//s:sheetData/s:row/s:c', ns):
                    col, row_number = position(cell.attrib['r'])
                    array_child = any(a[0] <= col <= b[0] and a[1] <= row_number <= b[1] for a,b in array_areas)
                    if cell.find('s:f', ns) is None and not array_child:
                        continue
                    current = calculated.get(cell.attrib['r'])
                    if current is None:
                        continue
                    number = current.find('s:v', ns)
                    kind = current.attrib.get('t', '')
                    new = number.text if number is not None else None
                    if kind == 's' and new is not None:
                        new, kind = strings[int(new)], 'str'
                    cell_updates[cell.attrib['r']] = (kind, new)
                for field, new in changes:
                    if field['sheet'] != name:
                        continue
                    kind = field['kind']
                    if kind == 'date':
                        new = stored_date(field, new)
                    elif kind == 'time':
                        new = stored_time(new)
                    text = kind not in {'date', 'time', 'percent', 'number'} or kind == 'date' and field.get('dateStorage') == 'text'
                    cell_updates[field['cell']] = ('inlineStr' if text else '', new)
                found = set()
                def replace(match):
                    address = match[1]
                    if address not in cell_updates:
                        return match[0]
                    found.add(address)
                    kind, new = cell_updates[address]
                    return patched_cell(match[0], address, kind, new)
                raw = re.sub(r'<c\b[^>]*\br="([A-Z]+[1-9][0-9]*)"[^>]*?(?:/>|>.*?</c>)', replace, raw, flags=re.S)
                raw = re.sub(r'<sheetData\b([^>]*)/>', r'<sheetData\1></sheetData>', raw)
                for address in set(cell_updates) - found:
                    kind, new = cell_updates[address]
                    new_cell = patched_cell(f'<c r="{address}"/>', address, kind, new)
                    row_number = int(re.search(r'\d+', address)[0])
                    row_pattern = rf'<row\b[^>]*\br="{row_number}"[^>]*?(?:/>|>.*?</row>)'
                    row_match = re.search(row_pattern, raw, re.S)
                    def order(a):
                        letters = re.match(r'[A-Z]+', a)[0]
                        result = 0
                        for letter in letters: result = result * 26 + ord(letter) - 64
                        return result
                    if row_match:
                        old_row = row_match[0]
                        if old_row.endswith('/>'):
                            new_row = old_row[:-2] + '>' + new_cell + '</row>'
                        else:
                            later = next((m for m in re.finditer(r'<c\b[^>]*\br="([A-Z]+[0-9]+)"', old_row) if order(m[1]) > order(address)), None)
                            at = later.start() if later else old_row.rfind('</row>')
                            new_row = old_row[:at] + new_cell + old_row[at:]
                        raw = raw[:row_match.start()] + new_row + raw[row_match.end():]
                    else:
                        later = next((m for m in re.finditer(r'<row\b[^>]*\br="([0-9]+)"', raw) if int(m[1]) > row_number), None)
                        at = later.start() if later else raw.find('</sheetData>')
                        if at < 0:
                            raise ValueError('A estrutura da guia nao permite inserir esta celula.')
                        raw = raw[:at] + f'<row r="{row_number}">{new_cell}</row>' + raw[at:]
                dimension = re.search(r'<dimension\b[^>]*\bref="([A-Z]+[0-9]+)(?::([A-Z]+[0-9]+))?"', raw)
                if dimension and cell_updates:
                    addresses = [dimension[1], dimension[2] or dimension[1], *cell_updates]
                    def coordinates(address):
                        letters, row = re.fullmatch(r'([A-Z]+)([0-9]+)', address).groups()
                        col = 0
                        for letter in letters: col = col * 26 + ord(letter) - 64
                        return col, int(row)
                    coords = [coordinates(address) for address in addresses]
                    def address(col, row):
                        letters = ''
                        while col:
                            col, digit = divmod(col - 1, 26)
                            letters = chr(65 + digit) + letters
                        return f'{letters}{row}'
                    lower = address(min(c for c,r in coords), min(r for c,r in coords))
                    upper = address(max(c for c,r in coords), max(r for c,r in coords))
                    new_dimension = re.sub(r'ref="[^"]*"', f'ref="{lower}:{upper}"', dimension[0])
                    raw = raw[:dimension.start()] + new_dimension + raw[dimension.end():]
                updates[part] = raw.encode('utf-8')
            with ZipFile(replacement, 'w') as output:
                for info in original.infolist():
                    output.writestr(info, updates.get(info.filename, original.read(info.filename)))
        os.replace(replacement, target)
    finally:
        replacement.unlink(missing_ok=True)


def worksheet_snapshot(book, body):
    name = body.get('worksheet')
    if not isinstance(name, str) or not name.strip() or len(name) > 31:
        raise ValueError('Selecione uma guia existente.')
    row, column = body.get('firstRow', 1), body.get('firstColumn', 1)
    if type(row) is not int or type(column) is not int or not 1 <= row <= 1048552 or not 1 <= column <= 16377:
        raise ValueError('Intervalo de consulta invalido.')
    sheet = book.Worksheets(name)
    table_headers = set()
    schedule_end = None
    consultation_end = None
    consultation_table_name = None
    def header_text(raw):
        return re.sub(r'[^a-z0-9]', '', unicodedata.normalize('NFKD', str(raw or '')).encode('ascii', 'ignore').decode().lower())
    for table in getattr(sheet, 'ListObjects', []):
        area = table.Range
        list_rows = getattr(table,'ListRows',None)
        data_rows = int(list_rows.Count) if list_rows is not None else int(area.Rows.Count)-1-int(bool(getattr(table,'ShowTotals',False)))
        if name.lower() == 'cronogramas' and row == 5 and column == 2 and int(area.Row) == 5 and int(area.Column) == 2 and str(sheet.Cells(5, 8).Value2).strip() == 'Status' and str(sheet.Cells(5, 9).Value2).startswith('Trabalho'):
            schedule_end = int(area.Row + area.Rows.Count - 1)
            if getattr(table, 'ShowTotals', False):
                schedule_end -= 1
            # Never silently calculate a partial schedule.
            if schedule_end > 2005:
                raise ValueError('Cronograma excede o limite de 2000 linhas.')
        if (int(area.Row) == 6 and int(area.Column) == 2 and
                str(sheet.Cells(2, 3).Value2).strip().casefold() == 'consultoria' and
                tuple(header_text(sheet.Cells(6,c).Value2) for c in range(2,10)) ==
                    ('data','manhainicio','manhafim','tardeinicio','tardefim','total','status','descricao') and
                (data_rows == 0 or bool(sheet.Cells(7,7).HasFormula))):
            if consultation_end is not None:
                raise ValueError('Mais de uma tabela de Consultoria foi encontrada.')
            consultation_end = 6 + data_rows
            consultation_table_name = getattr(table,'Name','')
            if not 6 <= consultation_end <= 2006:
                raise ValueError('Tabela de Consultoria fora do limite de 2000 encontros.')
        if getattr(table, 'ShowHeaders', True):
            table_headers.update((int(area.Row), c) for c in range(int(area.Column), int(area.Column + area.Columns.Count)))
    fields, formulas = [], []
    read_row = 6 if consultation_end is not None else row
    read_column = 2 if consultation_end is not None else column
    end_row = consultation_end if consultation_end is not None else schedule_end
    for r in range(read_row, end_row + 1 if end_row is not None else row + 25):
        for c in range(read_column, read_column + 8):
            cell = sheet.Cells(r, c)
            letters, index = '', c
            while index:
                index, digit = divmod(index - 1, 26)
                letters = chr(65 + digit) + letters
            address = f'{letters}{r}'
            raw, formula = cell.Value2, cell.Formula
            calculated = bool(cell.HasFormula)
            fmt = str(cell.NumberFormat).lower()
            kind = 'number' if isinstance(raw, (int, float)) and not isinstance(raw, bool) else 'text'
            if (kind == 'number' or raw is None) and re.search(r'[dy]|aa', re.sub(r'"[^"]*"|\\.', '', fmt)):
                kind = 'date'
            if (kind == 'number' or raw is None) and ':' in fmt and re.search(r'[hs]', fmt):
                kind = 'time'
            if consultation_end is not None and r > 6:
                if c == 2:
                    kind = 'date'
                elif 3 <= c <= 6:
                    kind = 'time'
            try:
                spill = bool(getattr(cell, 'HasSpill', False)) or bool(getattr(cell, 'HasArray', False))
            except Exception:
                spill = False
            readonly = calculated or spill or (r, c) in table_headers or bool(sheet.ProtectContents and cell.Locked) or bool(cell.MergeCells and cell.MergeArea.Cells(1,1).Address != cell.Address) or isinstance(raw, bool)
            if consultation_end is not None and c == 9 and r > 6:
                readonly = True  # The template's description is fixed by its summary/validation.
            fields.append({'sheet': name, 'cell': address, 'kind': kind, 'label': address,
                'group': 'Guia', 'value': value(cell, kind) if kind != 'number' else float(raw),
                'consultoriaStatus': consultation_end is not None and c == 8 and r > 6, 'scheduleStatus': schedule_end is not None and c == 8 and r > 5, 'percent': kind == 'number' and '%' in fmt, 'generic':True, 'readOnly': readonly, 'dateStorage':'number', 'display': str(cell.Text)})
            formulas.append([address, str(formula) if calculated else None])
    description = 'Consultoria'
    if consultation_end is not None:
        if consultation_end > 6:
            description = str(sheet.Cells(7,9).Value2 or 'Consultoria')
        else:
            for summary_table in getattr(sheet,'ListObjects',[]):
                r=int(summary_table.Range.Row)
                if r>6 and header_text(sheet.Cells(r,9).Value2)=='descricao':
                    description=str(sheet.Cells(r+1,9).Value2 or 'Consultoria')
                    break
    return {'fields': fields, 'tasks': [], 'consultoriaTable': consultation_end is not None,
        'consultoriaRowOperationsVersion': 2 if consultation_end is not None else None,
        'consultoriaDetails': {'tableName': consultation_table_name, 'description': description, 'client': str(sheet.Cells(2, 4).Text), 'contractedHours': value(sheet.Cells(3, 4), 'time')} if consultation_end is not None else None,
        'scheduleTable': schedule_end is not None, 'worksheetTypesVersion': 2, 'worksheet': name, 'firstRow':row, 'firstColumn':column,
        'formulaFingerprint': hashlib.sha256(json.dumps(formulas).encode()).hexdigest()}


def edit(path, body):
    path = Path(path)
    if path.suffix.lower() not in {'.xlsx', '.xlsm'} or path.stat().st_size > 25 * 1024 * 1024:
        raise ValueError('Use uma planilha XLSX ou XLSM de até 25 MB.')
    if not lock.acquire(blocking=False):
        raise ValueError('Aguarde a leitura ou gravação da planilha em andamento.')
    staged = None
    try:
        original = revision(path)
        if body['action'] == 'excel-editor-sheets':
            with workbook(path) as (_, book):
                names = [str(book.Worksheets(i).Name) for i in range(1, int(book.Worksheets.Count) + 1)]
            return {'sheetNames': names, 'revision': original, 'filename': path.name}
        writing = body['action'] == 'excel-editor-write'
        previewing = body['action'] == 'excel-editor-preview'
        if (writing or previewing) and body.get('revision') != original:
            raise ValueError('O arquivo mudou desde a leitura. Recarregue antes de salvar.')
        if not writing and not previewing:
            with workbook(path) as (_, book):
                data = worksheet_snapshot(book, body) if body.get('worksheet') is not None else snapshot(book, body.get('serviceType'), body.get('sheetNames'))
                if body.get('worksheet') is None:
                    data.update({'statusPreview': status_preview(book, body.get('serviceType'), body.get('sheetNames')),
                                 'statusPreviewRevision': original, 'statusPreviewSheets': body.get('sheetNames') or {}})
            if revision(path) != original:
                raise ValueError('O arquivo mudou durante a leitura. Recarregue.')
            return {**data, 'revision': original, 'filename': path.name}
        # With no draft changes, read the workbook's current status directly.
        # Creating a writable copy, scanning all fields and forcing a complete
        # recalculation here needlessly held the global Excel lock.
        if previewing and body.get('changes') == []:
            with workbook(path) as (_, book):
                preview = status_preview(book, body.get('serviceType'), body.get('sheetNames'))
            if revision(path) != original:
                raise ValueError('O arquivo mudou durante a previa. Recarregue para conferir.')
            return {'preview': True, 'statusPreview': preview, 'revision': original,
                    'entrySheet': (body.get('sheetNames') or {}).get('entry', 'Informa\u00e7\u00f5es de entrada'),
                    'checklistSheet': checklist_sheet(body.get('serviceType'), body.get('sheetNames')), 'filename': path.name}
        handle, name = tempfile.mkstemp(prefix='.gerenciador-', suffix=path.suffix, dir=path.parent)
        os.close(handle)
        staged = Path(name)
        shutil.copy2(path, staged)
        with workbook(staged, writable=True) as (app, book):
            before = worksheet_snapshot(book, body) if body.get('worksheet') is not None else snapshot(book, body.get('serviceType'), body.get('sheetNames'))
            from local_edesk.consultoria_rows import split_changes,plan as row_plan,apply as apply_rows
            payload = body.get('changes')
            normal, operations = ([],[]) if previewing and payload == [] else split_changes(payload)
            if operations and not writing:
                raise ValueError('Linhas so podem ser alteradas ao salvar a planilha.')
            changes = validated_changes(before, normal) if normal else []
            expected_rows = row_plan(before,changes,operations) if operations else None
            previous_calculation = app.Calculation if expected_rows is not None else None
            if expected_rows is not None:
                app.Calculation = -4135  # Batch row edits without recalculating after every cell.
            for field, new in changes:
                cell = book.Worksheets(field['sheet']).Range(field['cell'])
                try:
                    if cell.HasFormula:
                        raise ValueError('Uma célula de fórmula não pode ser editada.')
                    cell.Value2 = stored_date(field, new) if field['kind'] == 'date' else stored_time(new) if field['kind'] == 'time' else new
                finally:
                    # Release the Range proxy before closing/uninitializing COM.
                    cell = None
            if expected_rows is not None:
                apply_rows(book,before,expected_rows)
            app.CalculateFull()
            if expected_rows is not None:
                app.Calculation = previous_calculation
            if previewing:
                preview = status_preview(book, body.get('serviceType'), body.get('sheetNames'))
            else:
                book.Save()
        if previewing:
            if revision(path) != original:
                raise ValueError('O arquivo mudou durante a prévia. Recarregue para conferir.')
            return {'preview': True, 'statusPreview': preview, 'revision': original,
                    'entrySheet': (body.get('sheetNames') or {}).get('entry', 'Informa\u00e7\u00f5es de entrada'), 'checklistSheet': checklist_sheet(body.get('serviceType'), body.get('sheetNames')), 'filename': path.name}
        if expected_rows is not None:
            from local_edesk.consultoria_rows import preserve_assets_and_check
            preserve_assets_and_check(path,staged,body['worksheet'])
        else:
            preserve_package(path, staged, changes)
        with workbook(staged) as (_, book):
            checked = worksheet_snapshot(book, body) if body.get('worksheet') is not None else snapshot(book, body.get('serviceType'), body.get('sheetNames'))
        if expected_rows is not None:
            from local_edesk.consultoria_rows import verify as verify_rows
            verify_rows(checked,expected_rows)
        elif checked['formulaFingerprint'] != before['formulaFingerprint']:
            raise ValueError('Uma fórmula do modelo mudou. O original foi preservado.')
        mapped = {(f['sheet'], f['cell']): f['value'] for f in checked['fields'] + checked['tasks']}
        if expected_rows is None and any(mapped.get((f['sheet'], f['cell'])) != new for f, new in changes):
            raise ValueError('Não foi possível conferir os valores salvos. O original foi preservado.')
        if vba(staged) != vba(path):
            raise ValueError('As macros da cópia mudaram. O original foi preservado.')
        check_assets(path, staged)
        if revision(path) != original:
            raise ValueError('O arquivo mudou durante a gravação. O original foi preservado; recarregue.')
        backup_dir = path.parent / '.gerenciador-backups'
        backup_dir.mkdir(exist_ok=True)
        backup = backup_dir / f'{path.stem}-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:8]}{path.suffix}'
        shutil.copy2(path, backup)
        if revision(backup) != original or revision(path) != original:
            raise ValueError('O arquivo mudou durante o backup. Recarregue antes de salvar.')
        # Windows denies replacing a workbook opened by Excel. Never force it.
        try:
            os.replace(staged, path)
        except PermissionError:
            raise ValueError('Feche esta planilha no Excel e tente salvar novamente. O original foi preservado.') from None
        staged = None
        from local_edesk.backup_policy import prune_workbook_backups
        cleanup_warning = prune_workbook_backups(path, latest_backup=backup)
        return {**checked, 'revision': revision(path), 'filename': path.name,
                'saved': True, 'rowsApplied': {'added':len(expected_rows['added']),'deleted':len(expected_rows['deleted'])} if expected_rows is not None else None, 'backup': str(backup), 'backupCleanupWarning': cleanup_warning,
                'savedAt': datetime.now().isoformat()}
    finally:
        try:
            if staged is not None:
                try:
                    staged.unlink(missing_ok=True)
                except OSError:
                    # Excel/OneDrive can briefly keep this disposable copy
                    # open. Never mask the original result or strand the lock.
                    logging.getLogger(__name__).warning('A copia temporaria da planilha ficou pendente de limpeza.')
        finally:
            lock.release()
