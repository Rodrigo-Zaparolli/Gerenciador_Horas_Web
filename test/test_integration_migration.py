import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.migrate_integration_data import migrate


class MigrationTest(unittest.TestCase):
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
