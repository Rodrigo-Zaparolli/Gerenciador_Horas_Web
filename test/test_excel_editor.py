import copy
import os
import unittest
import tempfile
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET
from types import SimpleNamespace
from unittest.mock import patch
from local_edesk.excel_editor import allowed, validated_changes, preserve_package, value, stored_date, checklist_sheet, checklist_table
from local_edesk import local_files

os.environ['EDESK_LOCAL_MODE'] = 'true'


class ExcelEditorTests(unittest.TestCase):
    def test_schedule_snapshot_reads_the_whole_table_beyond_generic_page(self):
        from local_edesk.excel_editor import worksheet_snapshot
        def cell(r,c):
            raw = {8:'Status', 9:'Trabalho / Descricao'}.get(c, '') if r == 5 else ''
            return SimpleNamespace(Value2=raw, Formula='', HasFormula=False,
                NumberFormat='General', Text=raw, MergeCells=False)
        area = SimpleNamespace(Row=5, Column=2, Rows=SimpleNamespace(Count=41), Columns=SimpleNamespace(Count=8))
        table = SimpleNamespace(Range=area, ShowHeaders=True, ShowTotals=False)
        sheet = SimpleNamespace(ListObjects=[table],Cells=cell,ProtectContents=False)
        snapshot = worksheet_snapshot(SimpleNamespace(Worksheets=lambda name:sheet),
            {'worksheet':'Cronogramas','firstRow':5,'firstColumn':2})
        self.assertTrue(snapshot['scheduleTable'])
        self.assertEqual(len(snapshot['fields']),41*8)
        self.assertEqual(snapshot['fields'][-1]['cell'],'I45')
        self.assertTrue(snapshot['fields'][0]['readOnly'])
        area.Rows.Count=3000
        with self.assertRaises(ValueError):
            worksheet_snapshot(SimpleNamespace(Worksheets=lambda name:sheet),
                {'worksheet':'Cronogramas','firstRow':5,'firstColumn':2})

    def test_schedule_status_allows_numeric_and_named_values_but_never_formulas(self):
        field = {'sheet': 'Cronogramas', 'cell': 'H6', 'value': .99,
                 'kind': 'number', 'scheduleStatus': True, 'readOnly': False}
        current = {'fields': [field], 'tasks': []}
        for value in [0, .25, .5, .75, 1, .99, 'Programado', 'Cancelado']:
            result = validated_changes(current, [{'sheet':'Cronogramas', 'cell':'H6', 'before':.99, 'value':value}])
            self.assertEqual(result[0][1], value)
            self.assertEqual(result[0][0]['kind'], 'text' if isinstance(value,str) else 'number')
        for value in [True, -1, 2, float('nan'), '=1+1', 'Outro']:
            with self.assertRaises(ValueError):
                validated_changes(current, [{'sheet':'Cronogramas', 'cell':'H6', 'before':.99, 'value':value}])

    def test_maiQuel_access_uses_verified_identity_and_exact_email(self):
        self.assertTrue(allowed({'sub': 'maiQuel', 'email': ' MAIQUEL.ELSTE@CYNCLY.COM '}))
        self.assertFalse(allowed({'sub': '', 'email': 'maiQuel.elste@cyncly.com'}))
        self.assertTrue(allowed({'sub': 'other', 'email': 'other@example.com'}))

    def test_custom_sheet_names_override_only_named_tabs_and_reject_invalid_names(self):
        self.assertEqual(checklist_sheet('Professional', {'checklist': 'Professional CheckList-Processo'}), 'Professional CheckList-Processo')
        self.assertEqual(checklist_sheet('Enterprise', {'entry': 'Entrada'}), 'Checklist-Processo')
        for names in [{'checklist': ''}, {'entry': 'bad/name'}, {'checklist': 'x' * 32}, {'other': 'Sheet'}, ['Sheet'], {'entry': 'Sheet', 'checklist': 'sheet'}]:
            with self.subTest(names=names), self.assertRaises(ValueError):
                checklist_sheet('Enterprise', names)

    def test_listing_sheets_is_pilot_only_and_keeps_verified_identity(self):
        from urllib.parse import quote
        from cloud_run.main import app
        from local_edesk.files_server import app as files_app
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Project.xlsm'
            path.write_bytes(b'fixture')
            ref = 'desktop-file://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(path), safe='')
            headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake'}
            with patch.object(local_files, 'DB_PATH', Path(directory) / 'files.sqlite3'), patch('cloud_run.main.LOCAL_MODE', True):
                local_files._save('owner', ref, path, 'file')
                for server, verifier in [(app, 'local_edesk.authentication.verify_token'), (files_app, 'local_edesk.files_server.verify_token')]:
                    for email, status in [('rodrigozaparolli79@gmail.com', 200), ('maiquel.elste@cyncly.com', 200), ('other@example.com', 200)]:
                        with patch(verifier, return_value={'sub': 'owner', 'email': email}), patch('local_edesk.excel_editor.edit', return_value={'sheetNames': ['Entrada', 'Professional']}) as editor:
                            response = server.test_client().post('/api/local-files', headers=headers,
                                json={'action': 'excel-editor-sheets', 'reference': ref, 'email': 'rodrigozaparolli79@gmail.com'})
                            self.assertEqual(response.status_code, status, response.json)
                            self.assertEqual(editor.call_count, int(status == 200))

    def test_preview_receives_verified_claims_in_both_http_servers(self):
        from urllib.parse import quote
        from cloud_run.main import app
        from local_edesk.files_server import app as files_app
        headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake'}
        owner = {'sub': 'owner', 'email': 'rodrigozaparolli79@gmail.com'}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Project.xlsm'
            path.write_bytes(b'fixture')
            reference = 'desktop-file://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(path), safe='')
            with patch.object(local_files, 'DB_PATH', Path(directory) / 'files.sqlite3'), patch('cloud_run.main.LOCAL_MODE', True):
                local_files._save('owner', reference, path, 'file')
                for server, verifier in [(app, 'local_edesk.authentication.verify_token'), (files_app, 'local_edesk.files_server.verify_token')]:
                    with self.subTest(server=server.name):
                        with patch(verifier, return_value=owner), patch('local_edesk.excel_editor.edit', return_value={'preview': True}) as editor:
                            response = server.test_client().post('/api/local-files', headers=headers,
                                json={'action': 'excel-editor-preview', 'reference': reference, 'revision': 'test', 'changes': []})
                            self.assertEqual(response.status_code, 200, response.json)
                            self.assertTrue(response.json['preview'])
                            editor.assert_called_once()
                        with patch(verifier, return_value={**owner, 'sub': 'other', 'email': 'other@example.com'}), patch('local_edesk.excel_editor.edit') as editor:
                            response = server.test_client().post('/api/local-files', headers=headers,
                                json={'action': 'excel-editor-preview', 'reference': reference, 'email': owner['email']})
                            self.assertEqual(response.status_code, 400)
                            editor.assert_not_called()

    def test_project_kind_selects_only_the_requested_checklist(self):
        for kind in [None, '', 'Enterprise', 'Promob Enterprise']:
            self.assertEqual(checklist_sheet(kind), 'Checklist-Processo')
        for kind in ['Professional', 'Promob Professional', 'PROFISSIONAL Produção Completa']:
            self.assertEqual(checklist_sheet(kind), 'Maker Checklist-Processo')

    def test_table_header_and_rows_are_detected_for_both_models(self):
        for row, last in [(16, 223), (3, 42)]:
            table = SimpleNamespace(Range=SimpleNamespace(Row=row, Column=3,
                Columns=SimpleNamespace(Count=25), Rows=SimpleNamespace(Count=last-row+1)))
            sheet = SimpleNamespace(ListObjects=[table], Cells=lambda r, c:
                SimpleNamespace(Value2=('% Status Tarefas' if c == 5 else 'Tarefas') if r == row else ''))
            self.assertEqual(checklist_table(sheet), (row, last))
            sheet.ListObjects = [table, table]
            with self.assertRaises(ValueError): checklist_table(sheet)

    def test_block_headers_keep_distinct_identity_and_reset_at_stage_boundary(self):
        from local_edesk.excel_editor import checklist_tasks
        rows = {
            2: ('Implantacao', None, 'Instalacao'),
            3: ('Implantacao', 0, 'Instalar'),
            4: ('Implantacao', 1, 'Ativar'),
            5: ('Implantacao', None, 'Instalacao'),
            6: ('Implantacao', .5, 'Configurar'),
            7: ('Pos', .25, 'Revisar'),
        }
        def cell(row, column):
            values = rows[row]
            return SimpleNamespace(Value2={4:values[0],5:values[1],6:values[2],8:1/24,10:''}.get(column), HasFormula=False)
        tasks = checklist_tasks(SimpleNamespace(Name='Checklist', Cells=cell), 1, 7)
        self.assertEqual([t['blockId'] for t in tasks], ['Checklist!F2', 'Checklist!F2', 'Checklist!F5', ''])
        self.assertEqual([t['value'] for t in tasks], [0, 1, .5, .25])
        self.assertEqual(tasks[0]['block'], 'Instalacao')

    def test_timeline_exposes_only_table_dates_and_preserves_formulas(self):
        from local_edesk.excel_editor import timeline_fields
        table = SimpleNamespace(Name='DetalhesProjeto', Range=SimpleNamespace(Row=18, Column=1, Rows=SimpleNamespace(Count=4)))
        def cell(row, column):
            if row == 18: return SimpleNamespace(Value2='Data', HasFormula=False)
            if column == 2: return SimpleNamespace(Value2={19:'Contrato',20:'Implantacao',21:''}[row], HasFormula=False)
            return SimpleNamespace(Value2=46000, HasFormula=row == 19)
        sheet = SimpleNamespace(ListObjects=[table], Cells=cell)
        source = SimpleNamespace(Range=lambda address: SimpleNamespace(NumberFormat='dd/mm/yyyy'))
        book = SimpleNamespace(Worksheets=lambda name: source)
        with patch('local_edesk.excel_editor.SheetSnapshot', return_value=sheet):
            fields, _ = timeline_fields(book)
        self.assertEqual([f['cell'] for f in fields], ['C19','C20'])
        self.assertTrue(fields[0]['readOnly'])
        self.assertFalse(fields[1]['readOnly'])
        self.assertTrue(all(f['timeline'] and f['kind']=='date' for f in fields))
        with self.assertRaises(ValueError):
            validated_changes({'fields':fields,'tasks':[]}, [{'sheet':fields[0]['sheet'],'cell':'C19','before':fields[0]['value'],'value':'2026-10-23'}])
        self.assertEqual(len(validated_changes({'fields':fields,'tasks':[]}, [{'sheet':fields[1]['sheet'],'cell':'C20','before':fields[1]['value'],'value':'2026-10-23'}])),1)

    def setUp(self):
        self.field = {'sheet': 'entry', 'cell': 'C2', 'kind': 'text', 'value': 'old'}
        self.current = {'fields': [self.field], 'tasks': []}

    def change(self, **kwargs):
        return {'sheet': 'entry', 'cell': 'C2', 'before': 'old', 'value': 'new', **kwargs}

    def test_only_authenticated_owner_token_can_access(self):
        owner = {'sub': 'owner', 'email': 'rodrigozaparolli79@gmail.com', 'email_verified': True}
        self.assertTrue(allowed({'sub':'another', 'email':'another@example.com'}))
        self.assertTrue(allowed({'sub':'another'}))
        self.assertTrue(allowed(owner))
        self.assertTrue(allowed({**owner, 'email_verified': False}))
        self.assertTrue(allowed({'sub': 'owner', 'email': owner['email']}))
        for changes in [{'sub': ''}, {'sub': ' '}, {'sub': None}]:
            self.assertFalse(allowed({**owner, **changes}))
        with patch.object(local_files, '_connection') as db:
            for action in ['excel-editor-read', 'excel-editor-write', 'excel-editor-preview']:
                with self.assertRaises(PermissionError):
                    local_files.execute('other', {'action': action, 'email': owner['email']})
                with self.assertRaises(PermissionError):
                    local_files.execute('other', {'action': action}, verified_user=owner)
            db.assert_not_called()

    def test_endpoint_uses_authenticated_claims_and_not_body_email(self):
        from urllib.parse import quote
        from cloud_run.main import app
        headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake'}
        owner = {'sub': 'owner', 'email': 'rodrigozaparolli79@gmail.com', 'email_verified': False}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Project.xlsm'
            path.write_bytes(b'fixture')
            reference = 'desktop-file://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(path), safe='')
            with patch.object(local_files, 'DB_PATH', Path(directory) / 'files.sqlite3'), patch('cloud_run.main.LOCAL_MODE', True):
                local_files._save('owner', reference, path, 'file')
                with patch('local_edesk.authentication.verify_token', return_value=owner), patch('local_edesk.excel_editor.edit', return_value={'fields': [], 'tasks': []}) as editor:
                    response = app.test_client().post('/api/local-files', headers=headers,
                        json={'action': 'excel-editor-read', 'reference': reference})
                    self.assertEqual(response.status_code, 200, response.json)
                    editor.assert_called_once()
                with patch('local_edesk.authentication.verify_token', return_value={**owner, 'sub': 'other', 'email': 'other@example.com'}), patch('local_edesk.excel_editor.edit') as editor:
                    response = app.test_client().post('/api/local-files', headers=headers,
                        json={'action': 'excel-editor-read', 'reference': reference, 'email': owner['email'], 'email_verified': True})
                    self.assertEqual(response.status_code, 400)
                    editor.assert_not_called()

    def test_unmapped_duplicate_and_stale_values_rejected(self):
        self.assertEqual(validated_changes(self.current, [self.change()])[0][1], 'new')
        for changes in [[self.change(cell='Z9')], [self.change(), self.change()], [self.change(before='stale')], []]:
            with self.assertRaises(ValueError):
                validated_changes(self.current, changes)

    def test_formulas_rejected_as_user_text(self):
        for text in ['=SUM(A1:A2)', ' @lookup', '+1', '-1', 'x' * 10001]:
            with self.assertRaises(ValueError):
                validated_changes(self.current, [self.change(value=text)])

    def test_calculated_field_cannot_be_written(self):
        self.field['readOnly'] = True
        with self.assertRaises(ValueError):
            validated_changes(self.current, [self.change()])

    def test_package_preserves_assets_and_formulas_while_patching_only_values(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / 'source.xlsm', Path(directory) / 'target.xlsm'
            workbook = '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="entry" sheetId="1" r:id="rId1"/></sheets></workbook>'
            rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'
            original = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="2"><c r="C2" s="4"/><c r="D2"><f>1+1</f><v>0</v></c></row></sheetData></worksheet>'
            original = original.replace('</sheetData>', '<row r="3"><c r="H3"><f t="array" ref="H3:H4">SUMIFS(A:A,B:B,C3)</f><v>0</v></c></row><row r="4"><c r="H4"><v>0</v></c><c r="I4"><v>9</v></c></row></sheetData>')
            calculated = original.replace('<v>0</v>', '<v>2</v>').replace('<v>9</v>', '<v>99</v>')
            for path, xml in [(source, original), (target, calculated)]:
                with ZipFile(path, 'w') as archive:
                    archive.writestr('xl/workbook.xml', workbook)
                    archive.writestr('xl/_rels/workbook.xml.rels', rels)
                    archive.writestr('xl/worksheets/sheet1.xml', xml)
                    archive.writestr('xl/vbaProject.bin', b'original-vba' if path == source else b'recompiled')
                    archive.writestr('xl/media/image1.png', b'original-image' if path == source else b'recompressed')
            preserve_package(source, target, [(self.field, 'Text <&>')])
            with ZipFile(target) as archive:
                self.assertEqual(archive.read('xl/vbaProject.bin'), b'original-vba')
                self.assertEqual(archive.read('xl/media/image1.png'), b'original-image')
                root = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
                ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
                cells = root.findall('.//s:c', ns)
                self.assertEqual(cells[0].attrib['s'], '4')
                self.assertEqual(cells[0].find('s:is/s:t', ns).text, 'Text <&>')
                self.assertEqual(cells[1].find('s:f', ns).text, '1+1')
                self.assertEqual(cells[1].find('s:v', ns).text, '2')
                self.assertEqual(cells[2].find('s:f', ns).attrib['ref'], 'H3:H4')
                self.assertEqual(cells[3].find('s:v', ns).text, '2')
                self.assertEqual(cells[4].find('s:v', ns).text, '9')

    def test_date_yesno_and_percentage_domains(self):
        for kind, valid, invalid in [
            ('date', ['2026-10-19', ''], ['2026-02-30', '19/10/2026']),
            ('yesno', ['Sim', 'Não'], ['sim', 'Maybe']),
            ('percent', [0, .25, .5, .75, 1], [True, -1, 25, .3, float('nan')])]:
            current = copy.deepcopy(self.current)
            current['fields'][0]['kind'] = kind
            for value in valid:
                self.assertEqual(validated_changes(current, [self.change(value=value)])[0][1], value)
            for value in invalid:
                with self.assertRaises(ValueError):
                    validated_changes(current, [self.change(value=value)])

    def test_read_accepts_excel_dates_text_dates_and_template_instructions(self):
        for original, expected in [
            (None, ''), ('', ''), (0, ''), (46314, '2026-10-19'),
            ('19/10/2026', '2026-10-19'), ('19/10/26', '2026-10-19'),
            ('2026-10-19', '2026-10-19'), ('# Data da proposta #', '# Data da proposta #')]:
            self.assertEqual(value(SimpleNamespace(Value2=original), 'date'), expected)

    def test_date_save_preserves_text_or_numeric_storage(self):
        self.assertEqual(stored_date({'dateStorage': 'text'}, '2026-10-19'), '19/10/2026')
        self.assertEqual(stored_date({'dateStorage': 'number'}, '2026-10-19'), 46314)
        self.assertEqual(stored_date({'dateStorage': 'text'}, ''), '')
        self.assertIsNone(stored_date({'dateStorage': 'number'}, ''))


if __name__ == '__main__':
    unittest.main()
