import copy
import unittest
import tempfile
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET
from unittest.mock import patch
from local_edesk.excel_editor import allowed, validated_changes, preserve_package
from local_edesk import local_files


class ExcelEditorTests(unittest.TestCase):
    def setUp(self):
        self.field = {'sheet': 'entry', 'cell': 'C2', 'kind': 'text', 'value': 'old'}
        self.current = {'fields': [self.field], 'tasks': []}

    def change(self, **kwargs):
        return {'sheet': 'entry', 'cell': 'C2', 'before': 'old', 'value': 'new', **kwargs}

    def test_only_authenticated_owner_token_can_access(self):
        owner = {'sub': 'owner', 'email': 'rodrigozaparolli79@gmail.com', 'email_verified': True}
        self.assertTrue(allowed(owner))
        self.assertTrue(allowed({**owner, 'email_verified': False}))
        self.assertTrue(allowed({'sub': 'owner', 'email': owner['email']}))
        for changes in [{'email': 'other@example.com'}, {'sub': ''}, {'sub': ' '}, {'email': None}]:
            self.assertFalse(allowed({**owner, **changes}))
        with patch.object(local_files, '_connection') as db:
            for action in ['excel-editor-read', 'excel-editor-write']:
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
                with patch('local_edesk.authentication.verify_token', return_value={**owner, 'email': 'other@example.com'}), patch('local_edesk.excel_editor.edit') as editor:
                    response = app.test_client().post('/api/local-files', headers=headers,
                        json={'action': 'excel-editor-read', 'reference': reference, 'email': owner['email'], 'email_verified': True})
                    self.assertEqual(response.status_code, 403)
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
            calculated = original.replace('<v>0</v>', '<v>2</v>')
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


if __name__ == '__main__':
    unittest.main()
