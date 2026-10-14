"""Preserve an existing local SQLite database when replacing its service."""
import sqlite3
import sys
from contextlib import closing
from pathlib import Path


def migrate(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if source == destination or destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix('.migration.tmp')
    try:
        with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as old:
            with closing(sqlite3.connect(temporary)) as new:
                old.backup(new)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    migrate(sys.argv[1], sys.argv[2])
