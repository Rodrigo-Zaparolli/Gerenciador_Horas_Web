import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from scripts.diagnose_file_links import inspect_database


class FileLinksDiagnosticTests(unittest.TestCase):
    def test_missing_database_is_not_created(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'missing.sqlite3'
            self.assertEqual(inspect_database(path), {'exists': False})
            self.assertFalse(path.exists())

    def test_report_redacts_paths_uid_and_reference_and_does_not_change_database(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'links.sqlite3'
            with closing(sqlite3.connect(path)) as con, con:
                con.execute('CREATE TABLE files(uid,reference,path,kind)')
                con.execute('INSERT INTO files VALUES(?,?,?,?)',
                    ('private-uid', 'private-reference', str(Path(temporary)), 'folder'))
            before = path.read_bytes()
            report = inspect_database(path)
            self.assertEqual(report['grants'], 1)
            self.assertEqual(next(iter(report['accounts'].values()))['folder'], 1)
            self.assertNotIn('private-uid', str(report))
            self.assertNotIn('private-reference', str(report))
            self.assertNotIn(temporary, str(report))
            self.assertEqual(path.read_bytes(), before)

    def test_corrupt_database_is_reported_without_repair_or_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'links.sqlite3'
            path.write_bytes(b'not a database')
            self.assertEqual(inspect_database(path), {'exists': True, 'readable': False})
            self.assertEqual(path.read_bytes(), b'not a database')
