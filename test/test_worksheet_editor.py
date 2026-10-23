import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace
from zipfile import ZipFile
from xml.etree import ElementTree as ET
from local_edesk.excel_editor import worksheet_snapshot, validated_changes, preserve_package


class WorksheetTests(unittest.TestCase):
    def test_pages_rederive_types_and_protections_from_workbook(self):
        def cell(row, column):
            return SimpleNamespace(Value2=46000 if column == 1 else 5 if column == 2 else '',
                Formula='=1+4' if column == 2 else '', HasFormula=column == 2,
                NumberFormat='dd/mm/yyyy' if column == 1 else 'General',
                Locked=column == 3, MergeCells=False, Text='value')
        book = SimpleNamespace(Worksheets=lambda name: SimpleNamespace(Cells=cell, ProtectContents=True))
        page = worksheet_snapshot(book, {'worksheet':'Any sheet','firstRow':26,'firstColumn':1})
        self.assertEqual(len(page['fields']), 200)
        self.assertEqual(page['fields'][0]['cell'], 'A26')
        self.assertEqual(page['fields'][0]['kind'], 'date')
        self.assertTrue(page['fields'][1]['readOnly'])
        self.assertTrue(page['fields'][2]['readOnly'])
        self.assertFalse(page['fields'][3]['readOnly'])
        for address in ['B26', 'C26', 'A1']:
            with self.assertRaises(ValueError):
                validated_changes(page, [{'sheet':'Any sheet','cell':address,'before':'','value':'changed'}])
        field = page['fields'][3]
        changes = validated_changes(page, [{'sheet':'Any sheet','cell':field['cell'],'before':'','value':-12.5}])
        self.assertEqual(changes[0][0]['kind'], 'number')
        with self.assertRaises(ValueError):
            validated_changes(page, [{'sheet':'Any sheet','cell':field['cell'],'before':'','value':float('inf')}])

    def test_page_bounds_and_sheet_required(self):
        for args in [{}, {'worksheet':'x','firstRow':0}, {'worksheet':'x','firstColumn':16384}, {'worksheet':'x','firstRow':True}]:
            with self.assertRaises(ValueError):
                worksheet_snapshot(None,args)

    def test_new_cells_and_rows_preserve_macros_styles_and_formula(self):
        workbook = '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Any" sheetId="1" r:id="r1"/></sheets></workbook>'
        rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>'
        xml = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="C2:C2"/><sheetData><row r="2"><c r="C2" s="4"><f>1+1</f><v>2</v></c></row><row r="5"/></sheetData></worksheet>'
        with tempfile.TemporaryDirectory() as directory:
            source,target = Path(directory)/'a.xlsm',Path(directory)/'b.xlsm'
            for path in [source,target]:
                with ZipFile(path,'w') as z:
                    for name,data in [('xl/workbook.xml',workbook),('xl/_rels/workbook.xml.rels',rels),('xl/worksheets/sheet1.xml',xml),('xl/vbaProject.bin',b'macros')]:
                        z.writestr(name,data)
            changes = [({'sheet':'Any','cell':address,'kind':kind},value) for address,kind,value in [('B2','number',42),('D2','text','hello'),('A1','text','start'),('A5','text','end')]]
            preserve_package(source,target,changes)
            with ZipFile(target) as z:
                root=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
                ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
                self.assertEqual([r.get('r') for r in root.findall('m:sheetData/m:row',ns)],['1','2','5'])
                self.assertEqual([c.get('r') for c in root.findall('m:sheetData/m:row',ns)[1]],['B2','C2','D2'])
                self.assertEqual(root.find('.//m:c[@r="C2"]/m:f',ns).text,'1+1')
                self.assertEqual(root.find('.//m:c[@r="C2"]',ns).get('s'),'4')
                self.assertEqual(z.read('xl/vbaProject.bin'),b'macros')
                self.assertEqual(root.find('m:dimension',ns).get('ref'),'A1:D5')


if __name__ == '__main__':
    unittest.main()
