import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from local_edesk.backup_policy import prune_workbook_backups, remove_archived_backups


class BackupPolicyTests(unittest.TestCase):
    def test_five_per_exact_workbook_and_preserve_foreign_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            workbook = root / 'Cliente [1].xlsm'
            workbook.write_bytes(b'current')
            backups = root / '.gerenciador-backups'
            backups.mkdir()
            for i in range(9):
                (backups / f'Cliente [1]-20261020-12000{i}-abcdef12.xlsm').write_bytes(bytes([i]))
            other = backups / 'Cliente [10]-20261020-120000-abcdef12.xlsm'
            other.write_bytes(b'other')
            foreign = backups / 'Nao apagar.txt'
            foreign.write_text('manual')
            self.assertIsNone(prune_workbook_backups(workbook))
            self.assertEqual(sorted(p.read_bytes()[0] for p in backups.glob('*.xlsm') if p != other), list(range(4, 9)))
            self.assertEqual(other.read_bytes(), b'other')
            self.assertTrue(foreign.exists())
            self.assertEqual(workbook.read_bytes(), b'current')

    def test_delete_only_backups_within_confirmed_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            project = root / 'Finalizados' / 'Cliente'
            backup = project / 'Documentos' / '.gerenciador-backups'
            backup.mkdir(parents=True)
            (backup / 'Cliente-20261020-120000-abcdef12.xlsm').write_bytes(b'backup')
            original = backup.parent / 'Cliente.xlsm'
            original.write_bytes(b'original')
            other = root / 'Outro' / '.gerenciador-backups'
            other.mkdir(parents=True)
            (other / 'Outro-20261020-120000-abcdef12.xlsm').write_bytes(b'other')
            result = remove_archived_backups(project)
            self.assertTrue(result['complete'])
            self.assertEqual(result['removed'], 1)
            self.assertFalse(backup.exists())
            self.assertEqual(original.read_bytes(), b'original')
            self.assertTrue(other.exists())
            self.assertTrue(remove_archived_backups(project)['complete'])

    def test_locked_backup_reports_pending_and_retry_finishes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            backup = root / '.gerenciador-backups'
            backup.mkdir()
            path = backup / 'Cliente-20261020-120000-abcdef12.xlsm'
            path.write_bytes(b'backup')
            with patch.object(Path, 'unlink', side_effect=PermissionError('locked')):
                self.assertFalse(remove_archived_backups(root)['complete'])
            self.assertTrue(path.exists())
            self.assertTrue(remove_archived_backups(root)['complete'])

    def test_unknown_content_is_preserved_and_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            backup = root / '.gerenciador-backups'
            backup.mkdir()
            (backup / 'manual.txt').write_text('manual')
            self.assertFalse(remove_archived_backups(root)['complete'])
            self.assertTrue((backup / 'manual.txt').exists())


if __name__ == '__main__':
    unittest.main()
