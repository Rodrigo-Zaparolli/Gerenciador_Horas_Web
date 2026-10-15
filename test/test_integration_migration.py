import sqlite3
import os
import subprocess
import sys
from contextlib import closing
import tempfile
import unittest
from pathlib import Path

from scripts.migrate_integration_data import migrate


class MigrationTest(unittest.TestCase):
    def test_file_links_cli_imports_into_durable_database(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'old.sqlite3'
            destination = root / 'durable' / 'local-files.sqlite3'
            with closing(sqlite3.connect(source)) as old, old:
                old.execute('CREATE TABLE files(uid TEXT,reference TEXT,path TEXT,kind TEXT,PRIMARY KEY(uid,reference))')
                old.execute('INSERT INTO files VALUES(?,?,?,?)', ('owner', 'reference', r'C:\Clientes\Orquinare\Documentos', 'folder'))
            script = Path(__file__).resolve().parents[1] / 'scripts' / 'migrate_integration_data.py'
            result = subprocess.run([sys.executable, str(script), '--file-links', str(source)],
                cwd=root, env={**os.environ, 'EDESK_LOCAL_FILES_DB_PATH': str(destination)},
                capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            with closing(sqlite3.connect(destination)) as new:
                self.assertEqual(new.execute('SELECT uid,path FROM files').fetchone(), ('owner', r'C:\Clientes\Orquinare\Documentos'))
            self.assertTrue(source.exists())

    def test_preserves_committed_wal_data_and_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'old' / 'history.sqlite3'
            source.parent.mkdir()
            destination = Path(temporary) / 'new' / 'history.sqlite3'
            connection = sqlite3.connect(source)
            try:
                connection.execute('pragma journal_mode=WAL')
                connection.execute('create table entries(state text)')
                connection.execute("insert into entries values ('confirmed')")
                connection.commit()
                migrate(source, destination)
                with sqlite3.connect(destination) as copied:
                    self.assertEqual(copied.execute('select state from entries').fetchone(), ('confirmed',))
                copied.close()
                self.assertTrue(source.exists())
            finally:
                connection.close()

    def test_does_not_overwrite_existing_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'source.sqlite3'
            destination = Path(temporary) / 'existing.sqlite3'
            source.write_bytes(b'old')
            destination.write_bytes(b'existing')
            migrate(source, destination)
            self.assertEqual(destination.read_bytes(), b'existing')


if __name__ == '__main__':
    unittest.main()
