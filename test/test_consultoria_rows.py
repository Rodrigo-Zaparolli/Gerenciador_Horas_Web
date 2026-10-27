import unittest
import tempfile
from pathlib import Path
from zipfile import ZipFile
from copy import deepcopy
from local_edesk.consultoria_rows import split_changes,plan

class ConsultoriaRowsTests(unittest.TestCase):
    def before(self):
        return {'worksheet':'Consultorias','consultoriaTable':True,'consultoriaRowOperationsVersion':1,
            'consultoriaDetails':{'tableName':'table','description':'Consultoria'},
            'fields':[{'cell':f'{c}{r}','value':'Programado' if c=='H' else 'Consultoria' if c=='I' else '',
                'sheet':'Consultorias','kind':'text'} for r in [7,8] for c in 'BCDEFGHI']}
    def add(self,**values):
        return {'operation':'add-consultoria-row','id':'new-1','values':values}
    def test_split_only_explicit_known_operations(self):
        cell={'cell':'B7'};op=self.add()
        self.assertEqual(split_changes([cell,op]),([cell],[op]))
        for payload in [None,[],[{}]*501,[{'operation':'other'}],[None]]:
            with self.assertRaises(ValueError):split_changes(payload)
    def test_combination_preserves_source_and_validates_new_inputs(self):
        before=self.before();unchanged=deepcopy(before)
        expected=plan(before,[],[{'operation':'delete-consultoria-row','row':7},self.add(B='2026-12-01',C='08:00',D='10:00')])
        self.assertEqual(before,unchanged)
        self.assertEqual(len(expected['rows']),2)
        self.assertEqual(expected['rows'][-1]['C'],'08:00')
        self.assertEqual(expected['rows'][-1]['H'],'Programado')
        self.assertEqual(expected['deleted'],[7])
    def test_headers_outside_rows_and_duplicates_rejected(self):
        for ops in [[{'operation':'delete-consultoria-row','row':r}] for r in [6,9,True,'7']]+[
            [{'operation':'delete-consultoria-row','row':7}]*2,[self.add()]*2]:
            with self.assertRaises(ValueError):plan(self.before(),[],ops)
    def test_formula_invalid_date_time_status_and_unauthorized_columns_rejected(self):
        for values in [{'B':'2026-02-30'},{'C':'=1+1'},{'C':'not-time'},{'H':'Other'},{'H':.5},{'I':'Other project'},{'G':'02:00'},{'X':'x'}]:
            with self.assertRaises(ValueError):plan(self.before(),[],[self.add(**values)])
    def test_empty_and_delete_all_allowed_without_deleting_table(self):
        before=self.before()
        self.assertEqual(plan(before,[],[{'operation':'delete-consultoria-row','row':r} for r in [7,8]])['rows'],[])
        before['fields']=[]
        self.assertEqual(len(plan(before,[],[self.add()])['rows']),1)
    def test_copied_description_cannot_inject_a_formula(self):
        before=self.before();before['consultoriaDetails']['description']='=1+1'
        with self.assertRaises(ValueError):plan(before,[],[self.add()])
    def test_other_models_never_accept_row_operations(self):
        for key in ['consultoriaTable','consultoriaRowOperationsVersion']:
            before=self.before();before[key]=False
            with self.assertRaises(ValueError):plan(before,[],[self.add()])

class PackagePreservationTests(unittest.TestCase):
    def package(self,path,changed=False,bad_literal=False):
        ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
        workbook=f'<workbook xmlns="{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Consultorias" r:id="a"/><sheet name="Outra" r:id="b"/></sheets></workbook>'
        rels='<Relationships><Relationship Id="a" Target="worksheets/sheet1.xml"/><Relationship Id="b" Target="worksheets/sheet2.xml"/></Relationships>'
        with ZipFile(path,'w') as z:
            z.writestr('xl/workbook.xml',workbook);z.writestr('xl/_rels/workbook.xml.rels',rels)
            z.writestr('xl/worksheets/sheet1.xml',f'<worksheet xmlns="{ns}"><sheetData/></worksheet>')
            text='CHANGED' if bad_literal else 'KEEP'
            z.writestr('xl/worksheets/sheet2.xml',f'<worksheet xmlns="{ns}"><sheetData><row r="1"><c r="B1" t="inlineStr"><is><t>{text}</t></is></c><c r="C1"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>')
            for name in ['xl/vbaProject.bin','xl/media/image.png','xl/activeX/activeX1.xml']:
                z.writestr(name,b'changed' if changed else b'original')
    def test_restore_assets_and_reject_changes_to_other_sheet_data(self):
        from local_edesk.consultoria_rows import preserve_assets_and_check
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'source.xlsm';target=Path(folder)/'target.xlsm'
            self.package(source);self.package(target,changed=True)
            preserve_assets_and_check(source,target,'Consultorias')
            with ZipFile(target) as z:
                self.assertEqual(z.read('xl/vbaProject.bin'),b'original')
                self.assertEqual(z.read('xl/media/image.png'),b'original')
                self.assertEqual(z.read('xl/activeX/activeX1.xml'),b'original')
            self.package(target,changed=True,bad_literal=True)
            before=source.read_bytes()
            with self.assertRaises(ValueError):preserve_assets_and_check(source,target,'Consultorias')
            self.assertEqual(source.read_bytes(),before)

if __name__=='__main__':unittest.main()
