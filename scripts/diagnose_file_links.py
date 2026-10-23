"""Read-only local link diagnostics. Never exports credentials, keys or paths."""
import hashlib
import json
import os
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
from urllib.request import urlopen


def inspect_database(path):
    path = Path(path)
    report = {'exists': path.is_file()}
    if not report['exists']:
        return report
    try:
        with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)) as con:
            rows = con.execute('SELECT uid,reference,path,kind FROM files').fetchall()
        accounts = {}
        for uid, reference, resource, kind in rows:
            account = hashlib.sha256(str(uid).encode()).hexdigest()[:12]
            summary = accounts.setdefault(account, {'folder': 0, 'file': 0,
                'missingPaths': 0, 'desktopReferences': 0, 'legacyReferences': 0})
            if kind in {'folder', 'file'}:
                summary[kind] += 1
            summary['missingPaths'] += not Path(resource).exists()
            summary['desktopReferences' if str(reference).startswith('desktop-') else 'legacyReferences'] += 1
        report.update(readable=True, grants=len(rows), accounts=accounts)
    except (sqlite3.DatabaseError, OSError):
        report['readable'] = False
    return report


def main():
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root))
    from local_edesk import local_files
    stable = local_files.DB_PATH
    key = stable.with_name(stable.name + '.key')
    report = {
        'diagnostic': 'file-links-read-only-1',
        'stableLocation': 'custom' if os.environ.get('EDESK_LOCAL_FILES_DB_PATH') else 'Windows user profile',
        'stableDatabase': inspect_database(stable),
        'recoveryDatabase': inspect_database(local_files._recovery_path()),
        'legacyDatabase': inspect_database(local_files.LEGACY_DB_PATH),
        'signingKeyPresent': key.is_file(),
        'signingKeySizeValid': key.is_file() and key.stat().st_size == 32,
    }
    try:
        with urlopen('http://127.0.0.1:8765/healthz', timeout=3) as response:
            health = json.load(response)
        report['activeIntegration'] = {name: health.get(name) for name in
            ['service', 'mode', 'integrationPackageVersion', 'nativeFilesVersion', 'durableLocalLinks']}
    except Exception:
        report['activeIntegration'] = 'not reachable'
    # Console only: no database creation, migrations, pickers or key generation.
    print(json.dumps(report, indent=2, ensure_ascii=True))


if __name__ == '__main__':
    main()
