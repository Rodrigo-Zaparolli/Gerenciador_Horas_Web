import tempfile,threading,unittest
from pathlib import Path
from contextlib import contextmanager
from unittest.mock import patch
from local_edesk import excel_editor

class ExcelOperationCleanupTests(unittest.TestCase):
 def test_locked_temporary_copy_cannot_strand_excel_lock_or_mask_original_error(self):
  with tempfile.TemporaryDirectory() as directory:
   source=Path(directory)/'project.xlsm';source.write_bytes(b'fixture')
   guard=threading.Lock()
   with patch.object(excel_editor,'lock',guard),patch.object(excel_editor,'revision',return_value='rev'),patch.object(excel_editor,'workbook',side_effect=RuntimeError('original Excel error')),patch.object(Path,'unlink',side_effect=PermissionError('fixture locked copy')):
    with self.assertLogs(excel_editor.__name__,level='WARNING'):
     with self.assertRaisesRegex(RuntimeError,'original Excel error'):
      excel_editor.edit(source,{'action':'excel-editor-preview','revision':'rev','changes':[{}]})
    self.assertTrue(guard.acquire(blocking=False))
    guard.release()

 def test_unchanged_preview_is_read_only_without_copy_snapshot_or_full_recalculation(self):
  @contextmanager
  def opened(path,writable=False):
   self.assertFalse(writable)
   yield None,object()
  with tempfile.TemporaryDirectory() as directory:
   source=Path(directory)/'project.xlsm';source.write_bytes(b'fixture')
   before=source.read_bytes()
   with patch.object(excel_editor,'lock',threading.Lock()),patch.object(excel_editor,'revision',return_value='rev'),patch.object(excel_editor,'workbook',opened),patch.object(excel_editor,'snapshot',side_effect=AssertionError('unnecessary snapshot')),patch.object(excel_editor.tempfile,'mkstemp',side_effect=AssertionError('unnecessary writable copy')),patch.object(excel_editor,'status_preview',return_value={'total':.6,'rows':[]}) as status:
    result=excel_editor.edit(source,{'action':'excel-editor-preview','revision':'rev','changes':[],'serviceType':'Professional'})
   self.assertTrue(result['preview']);self.assertEqual(result['statusPreview']['total'],.6)
   status.assert_called_once();self.assertEqual(source.read_bytes(),before)
   self.assertEqual(list(Path(directory).iterdir()),[source])

if __name__=='__main__':unittest.main()
