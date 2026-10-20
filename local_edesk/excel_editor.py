"""Pilot editor: mapped cells only, Excel COM, staged writes and file revision checks."""
from contextlib import contextmanager
from datetime import datetime, timedelta
import hashlib
import json
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
import posixpath
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

OWNER = 'rodrigozaparolli79@gmail.com'
lock = threading.Lock()
BASE = datetime(1899, 12, 30)


def allowed(user):
    return (bool(user.get('sub')) and user.get('email_verified') is True
            and str(user.get('email', '')).strip().lower() == OWNER)


def revision(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


@contextmanager
def workbook(path, writable=False):
    import pythoncom
    import win32com.client
    pythoncom.CoInitialize()
    app = book = None
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
        yield app, book
    finally:
        if book is not None:
            book.Close(SaveChanges=False)
        if app is not None:
            app.Quit()
        pythoncom.CoUninitialize()


def value(cell, kind):
    raw = cell.Value2
    if kind == 'date':
        return (BASE + timedelta(days=float(raw))).strftime('%Y-%m-%d') if raw else ''
    if kind == 'percent':
        return float(raw or 0)
    if raw is None:
        return ''
    return str(int(raw)) if isinstance(raw, float) and raw.is_integer() else str(raw)


class SheetSnapshot:
    """Read cells in two COM calls instead of thousands of RPC calls."""
    def __init__(self, sheet):
        self.Name = sheet.Name
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


def snapshot(book):
    entry = SheetSnapshot(book.Worksheets('Informações de entrada'))
    checklist = SheetSnapshot(book.Worksheets('Checklist-Processo'))
    table = checklist.ListObjects('Tab_Check_List')
    if (str(checklist.Cells(16, 5).Value2).strip() != '% Status Tarefas'
            or str(checklist.Cells(16, 6).Value2).strip() != 'Tarefas'):
        raise ValueError('O modelo do checklist é diferente. Nenhuma célula será alterada.')
    fields, tasks = [], []

    def add(sheet, address, label, group, kind='text'):
        cell = sheet.Range(address)
        fields.append({'sheet': sheet.Name, 'cell': address, 'label': label,
                       'group': group, 'kind': kind, 'value': value(cell, kind),
                       'readOnly': bool(cell.HasFormula)})

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
    last = min(int(table.Range.Row + table.Range.Rows.Count - 1), 500)
    for row in range(17, last + 1):
        description = str(checklist.Cells(row, 6).Value2 or '').strip()
        cell = checklist.Cells(row, 5)
        raw = cell.Value2
        if not description or cell.HasFormula or not isinstance(raw, (int, float)):
            continue
        if isinstance(raw, bool) or not 0 <= raw <= 1:
            continue
        estimate = checklist.Cells(row, 8).Value2
        minutes = round(float(estimate) * 1440) if isinstance(estimate, (int, float)) else 0
        tasks.append({'sheet': checklist.Name, 'cell': f'E{row}', 'kind': 'percent',
                      'value': float(raw), 'label': description,
                      'group': str(checklist.Cells(row, 4).Value2 or ''),
                      'estimated': f'{minutes // 60:02}:{minutes % 60:02}',
                      'note': str(checklist.Cells(row, 10).Value2 or '')})
    progress = checklist.Range('T15').Value2
    formulas = [(sheet.Name, row, column, formula)
                for sheet in [entry, checklist]
                for row, values in enumerate(sheet.formulas, 1)
                for column, formula in enumerate(values, 1)
                if isinstance(formula, str) and formula.startswith('=')]
    return {'fields': fields, 'tasks': tasks,
            'formulaFingerprint': hashlib.sha256(json.dumps(formulas).encode()).hexdigest(),
            'formulaCount': len(formulas),
            'progress': float(progress) if isinstance(progress, (int, float)) and 0 <= progress <= 1 else None}


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
        if kind == 'percent':
            if isinstance(new, bool) or not isinstance(new, (int, float)) or not math.isfinite(new) or new not in {0, .25, .5, .75, 1}:
                raise ValueError('Use 0%, 25%, 50%, 75% ou 100%.')
        elif not isinstance(new, str) or len(new) > 10000:
            raise ValueError('Texto inválido ou muito longo.')
        elif kind == 'yesno' and new not in {'Sim', 'Não'}:
            raise ValueError('Selecione Sim ou Não.')
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
                for cell in old_root.findall('.//s:sheetData/s:row/s:c', ns):
                    if cell.find('s:f', ns) is None:
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
                        new = (datetime.strptime(new, '%Y-%m-%d') - BASE).days if new else None
                    cell_updates[field['cell']] = ('' if kind in {'date', 'percent'} else 'inlineStr', new)
                found = set()
                def replace(match):
                    address = match[1]
                    if address not in cell_updates:
                        return match[0]
                    found.add(address)
                    kind, new = cell_updates[address]
                    return patched_cell(match[0], address, kind, new)
                raw = re.sub(r'<c\b[^>]*\br="([A-Z]+[1-9][0-9]*)"[^>]*?(?:/>|>.*?</c>)', replace, raw, flags=re.S)
                if set(cell_updates) - found:
                    raise ValueError('Uma célula não foi localizada no arquivo original.')
                updates[part] = raw.encode('utf-8')
            with ZipFile(replacement, 'w') as output:
                for info in original.infolist():
                    output.writestr(info, updates.get(info.filename, original.read(info.filename)))
        os.replace(replacement, target)
    finally:
        replacement.unlink(missing_ok=True)


def edit(path, body):
    path = Path(path)
    if path.suffix.lower() not in {'.xlsx', '.xlsm'} or path.stat().st_size > 25 * 1024 * 1024:
        raise ValueError('Use uma planilha XLSX ou XLSM de até 25 MB.')
    if not lock.acquire(blocking=False):
        raise ValueError('Aguarde a leitura ou gravação da planilha em andamento.')
    staged = None
    try:
        original = revision(path)
        writing = body['action'] == 'excel-editor-write'
        if writing and body.get('revision') != original:
            raise ValueError('O arquivo mudou desde a leitura. Recarregue antes de salvar.')
        if not writing:
            with workbook(path) as (_, book):
                data = snapshot(book)
            if revision(path) != original:
                raise ValueError('O arquivo mudou durante a leitura. Recarregue.')
            return {**data, 'revision': original, 'filename': path.name}
        handle, name = tempfile.mkstemp(prefix='.gerenciador-', suffix=path.suffix, dir=path.parent)
        os.close(handle)
        staged = Path(name)
        shutil.copy2(path, staged)
        with workbook(staged, writable=True) as (app, book):
            before = snapshot(book)
            changes = validated_changes(before, body.get('changes'))
            for field, new in changes:
                cell = book.Worksheets(field['sheet']).Range(field['cell'])
                if cell.HasFormula:
                    raise ValueError('Uma célula de fórmula não pode ser editada.')
                cell.Value2 = ((datetime.strptime(new, '%Y-%m-%d') - BASE).days if new else None) if field['kind'] == 'date' else new
            app.CalculateFull()
            book.Save()
        preserve_package(path, staged, changes)
        with workbook(staged) as (_, book):
            checked = snapshot(book)
        if checked['formulaFingerprint'] != before['formulaFingerprint']:
            raise ValueError('Uma fórmula do modelo mudou. O original foi preservado.')
        mapped = {(f['sheet'], f['cell']): f['value'] for f in checked['fields'] + checked['tasks']}
        if any(mapped.get((f['sheet'], f['cell'])) != new for f, new in changes):
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
        return {**checked, 'revision': revision(path), 'filename': path.name,
                'saved': True, 'backup': str(backup), 'savedAt': datetime.now().isoformat()}
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)
        lock.release()
