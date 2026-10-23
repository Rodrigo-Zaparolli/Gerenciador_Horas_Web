"""User-selected Windows paths, scoped to Firebase UID, never supplied to startfile by HTTP."""
import base64
import hashlib
import hmac
import json
import logging
import ntpath
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid
from contextlib import closing, contextmanager
from pathlib import Path, PureWindowsPath
from urllib.parse import quote, unquote, urlsplit

LEGACY_DB_PATH = Path(__file__).resolve().parent.parent / '.edesk-local' / 'local-files.sqlite3'


def database_path():
    override = os.environ.get('EDESK_LOCAL_FILES_DB_PATH')
    if override:
        return Path(override).expanduser().resolve()
    local_data = Path(os.environ.get('LOCALAPPDATA') or Path.home() / 'AppData' / 'Local')
    return local_data / 'GerenciadorHoras' / 'integracao' / 'local-files.sqlite3'


DB_PATH = database_path()
EXTENSIONS = {'.xlsx', '.xls', '.xlsm', '.csv', '.doc', '.docx', '.pdf', '.txt'}
picker_lock = threading.Lock()
recovery_lock = threading.Lock()
key_lock = threading.Lock()
database_lock = threading.Lock()
PROTOCOL_VERSION = 'persistent-file-links-7'
DURABLE_LINKS = True
PROJECT_LINK_RECOVERY = True
SPREADSHEET_LAYOUTS = ('enterprise', 'professional-maker')
PROJECT_ROOT_MOVE = True
VERIFIED_PROJECT_MOVE = True
SPREADSHEET_SHEET_NAMES = True
SUPPORTED_ACTIONS = frozenset({'authorize', 'pick-file', 'pick-folder', 'create-folder', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'excel-editor-preview', 'excel-editor-sheets', 'project-move-prepare', 'project-move-commit'})


def _absolute_windows_path(value):
    return (isinstance(value, str) and len(value) <= 4096
            and not re.search(r'[\x00-\x1f]', value)
            and PureWindowsPath(value).is_absolute())


def _expected_path(reference):
    if _absolute_windows_path(reference):
        return reference
    uri = urlsplit(reference)
    if uri.scheme in {'desktop-file', 'desktop-folder'}:
        label = unquote(uri.path.split('/')[-1])
        if _absolute_windows_path(label):
            return label
    return None


def _same_path(first, second):
    # Windows path casing must not conflate distinct Unicode names (ß/ss).
    return ntpath.normcase(str(PureWindowsPath(str(first)))).rstrip('\\/') == ntpath.normcase(str(PureWindowsPath(str(second)))).rstrip('\\/')


def _check_expected_path(reference, path):
    expected = _expected_path(reference)
    if expected is not None and not _same_path(expected, path):
        raise ValueError('A pasta ou planilha selecionada não corresponde ao caminho salvo. Selecione o destino correto no editor deste trabalho.')


def _signing_key(create=False):
    # Kept in the Windows profile, never in a downloaded/extracted package or
    # sent to the web app. A reference alone cannot grant a new filesystem path.
    location = DB_PATH.with_name(DB_PATH.name + '.key')
    with key_lock:
        try:
            key = location.read_bytes()
        except FileNotFoundError:
            if not create:
                return None
            location.parent.mkdir(parents=True, exist_ok=True)
            try:
                descriptor = os.open(location, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                key = location.read_bytes()
            else:
                key = secrets.token_bytes(32)
                with os.fdopen(descriptor, 'wb') as file:
                    file.write(key)
                    file.flush()
                    os.fsync(file.fileno())
        # Another service process may have exclusively created the key just
        # before writing its 32 bytes. Never replace that process's key.
        for _ in range(10):
            if key:
                break
            time.sleep(.02)
            key = location.read_bytes()
        if len(key) != 32:
            raise ValueError('A chave local dos vínculos não pôde ser lida. Seus caminhos foram preservados; reinicie a integração.')
        return key


def _signed_id(uid, path, kind, key):
    normalized = PureWindowsPath(str(path)).as_posix().rstrip('/')
    message = json.dumps(['file-link-v1', uid, kind, normalized], ensure_ascii=False,
                         separators=(',', ':')).encode('utf-8')
    return str(uuid.UUID(bytes=hmac.new(key, message, hashlib.sha256).digest()[:16], version=4))


def signed_reference(uid, path, kind):
    identity = _signed_id(uid, path, kind, _signing_key(create=True))
    return f'desktop-{kind}://local/{quote(uid, safe="")}/{identity}/{quote(str(path), safe="")}'


def _signed_authorization(uid, reference, kind):
    # Called only after parse_reference checked account, shape and resource kind.
    if not reference.startswith(f'desktop-{kind}://'):
        return None
    expected = _expected_path(reference)
    key = _signing_key()
    if expected is None or key is None:
        return None
    identity = urlsplit(reference).path.split('/')[2]
    if hmac.compare_digest(identity, _signed_id(uid, expected, kind, key)):
        return expected, kind
    return None


def parse_reference(reference, uid):
    # Legacy editor paths also require a one-time native selection; never open
    # the client-provided path directly, even if it already exists.
    if _absolute_windows_path(reference):
        legacy = PureWindowsPath(reference)
        return ('file' if legacy.suffix.lower() in EXTENSIONS else 'folder'), legacy.name or legacy.anchor
    uri = urlsplit(reference)
    parts = [unquote(part) for part in uri.path.split('/')[1:]]
    if (uri.scheme not in {'browser-file', 'browser-folder', 'desktop-file', 'desktop-folder'}
            or uri.netloc != 'local' or uri.query or uri.fragment or len(parts) != 3
            or parts[0] != uid or not re.fullmatch(r'[0-9a-f-]{36}', parts[1])
            or not parts[2]):
        raise ValueError('Vínculo local inválido para esta conta.')
    if '/' in parts[2] or '\\' in parts[2]:
        if not uri.scheme.startswith('desktop-') or not _absolute_windows_path(parts[2]):
            raise ValueError('Caminho local inválido.')
        label = PureWindowsPath(parts[2])
        return ('folder' if uri.scheme.endswith('folder') else 'file'), label.name or label.anchor
    return ('folder' if uri.scheme.endswith('folder') else 'file'), parts[2]


def choose(kind, title):
    # Each Tk instance is created, used and destroyed on the same request thread.
    import tkinter as tk
    from tkinter import filedialog
    root = tk.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    try:
        if kind == 'folder':
            return filedialog.askdirectory(parent=root, title=title)
        return filedialog.askopenfilename(parent=root, title=title,
            filetypes=[('Documentos do projeto', '*.xlsx *.xls *.xlsm *.csv *.doc *.docx *.pdf *.txt')])
    finally:
        root.destroy()


def _validate(path, kind):
    value = Path(path).resolve(strict=True)
    if kind == 'folder' and not value.is_dir():
        raise ValueError('Selecione uma pasta.')
    if kind == 'file' and (not value.is_file() or value.suffix.lower() not in EXTENSIONS):
        raise ValueError('Selecione uma planilha ou documento do projeto.')
    return value


def _open_database():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with database_lock:
        con = sqlite3.connect(DB_PATH, timeout=10)
        try:
            con.execute('PRAGMA schema_version').fetchone()
            return con
        except sqlite3.DatabaseError as error:
            con.close()
            if getattr(error, 'sqlite_errorcode', None) not in {sqlite3.SQLITE_CORRUPT, sqlite3.SQLITE_NOTADB}:
                raise
            # Keep the damaged index and its sidecars for recovery; never
            # overwrite the grant backup or discard the installation key.
            root = DB_PATH.parent.resolve()
            quarantine = DB_PATH.with_name(DB_PATH.name + '.corrupt-' + uuid.uuid4().hex)
            for suffix in ('', '-wal', '-shm', '-journal'):
                source = DB_PATH.with_name(DB_PATH.name + suffix)
                target = quarantine.with_name(quarantine.name + suffix)
                if source.exists():
                    if source.resolve().parent != root or target.resolve().parent != root:
                        raise ValueError('O índice local precisa de recuperação manual; nenhum caminho foi alterado.')
                    os.replace(source, target)
            logging.getLogger(__name__).warning('Indice local danificado preservado; recuperando autorizacoes nativas.')
            return sqlite3.connect(DB_PATH, timeout=10)


@contextmanager
def _connection():
    con = _open_database()
    try:
        with con:
            had_files = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='files'").fetchone()
            con.execute('CREATE TABLE IF NOT EXISTS files(uid TEXT, reference TEXT, path TEXT, kind TEXT, PRIMARY KEY(uid,reference))')
            if not had_files:
                _restore_authorizations(con)
            _import_legacy(con)
            yield con
        if con.total_changes or not _recovery_path().exists():
            _backup_authorizations(con)
    finally:
        con.close()


def _recovery_path():
    return DB_PATH.with_name(DB_PATH.name + '.authorizations.sqlite3')


def _restore_authorizations(con):
    recovery = _recovery_path()
    if not recovery.is_file():
        return
    try:
        with closing(sqlite3.connect(recovery.resolve().as_uri() + '?mode=ro', uri=True, timeout=10)) as saved:
            rows = saved.execute('SELECT uid,reference,path,kind FROM files').fetchall()
        con.executemany('INSERT OR IGNORE INTO files VALUES(?,?,?,?)', rows)
    except sqlite3.DatabaseError:
        logging.getLogger(__name__).warning('A copia local de autorizacoes nao pode ser recuperada.')


def _backup_authorizations(con):
    # Only native grants already committed for this Windows user are copied.
    # Never rebuild permissions from a path supplied by a web request.
    recovery = _recovery_path()
    temporary = recovery.with_name(recovery.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with recovery_lock:
            rows = con.execute('SELECT uid,reference,path,kind FROM files').fetchall()
            with closing(sqlite3.connect(temporary)) as saved:
                with saved:
                    saved.execute('CREATE TABLE files(uid TEXT,reference TEXT,path TEXT,kind TEXT,PRIMARY KEY(uid,reference))')
                    saved.executemany('INSERT INTO files VALUES(?,?,?,?)', rows)
            os.replace(temporary, recovery)
    except (OSError, sqlite3.DatabaseError):
        logging.getLogger(__name__).warning('Autorizacoes salvas; a copia de recuperacao local ficou pendente.')
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            logging.getLogger(__name__).warning('Arquivo temporario da recuperacao local ainda esta em uso.')


def _import_legacy(con, source_path=None):
    """Merge authorizations from this extraction without replacing other links.

    The stable database survives extracting a new package into another folder.
    Reimport a legacy database when it changes: an older installation may
    have received new native selections after the first migration.
    """
    legacy = Path(source_path or LEGACY_DB_PATH).resolve()
    if legacy == DB_PATH.resolve() or not legacy.is_file():
        return
    con.execute('CREATE TABLE IF NOT EXISTS imported_file_databases(source TEXT PRIMARY KEY)')
    columns = {row[1] for row in con.execute('PRAGMA table_info(imported_file_databases)')}
    if 'fingerprint' not in columns:
        try:
            con.execute('ALTER TABLE imported_file_databases ADD COLUMN fingerprint TEXT')
        except sqlite3.OperationalError as error:
            if 'duplicate column' not in str(error).lower():
                raise
    source = str(legacy)
    fingerprints = []
    for file in (legacy, legacy.with_name(legacy.name + '-wal')):
        if file.exists():
            info = file.stat()
            fingerprints.append((info.st_size, info.st_mtime_ns, info.st_ino))
    fingerprint = repr(fingerprints)
    imported = con.execute('SELECT fingerprint FROM imported_file_databases WHERE source=?', (source,)).fetchone()
    if imported and imported[0] == fingerprint:
        return
    try:
        with closing(sqlite3.connect(legacy.as_uri() + '?mode=ro', uri=True, timeout=10)) as old:
            rows = old.execute('SELECT uid,reference,path,kind FROM files').fetchall()
    except sqlite3.DatabaseError:
        logging.getLogger(__name__).warning('Indice antigo ilegivel preservado; usando os vinculos persistentes deste computador.')
        return
    con.executemany('INSERT OR IGNORE INTO files(uid,reference,path,kind) VALUES(?,?,?,?)', rows)
    con.execute('INSERT INTO imported_file_databases(source,fingerprint) VALUES(?,?) '
                'ON CONFLICT(source) DO UPDATE SET fingerprint=excluded.fingerprint', (source, fingerprint))


def import_authorizations(source):
    with _connection() as con:
        _import_legacy(con, source)


def _authorized_path(con, uid, reference, kind):
    """Recover a changed reference only from this account's exact approved path.

    Names such as Documentos are never used to associate different projects.
    Metadata from the web alone does not authorize a new filesystem path.
    """
    expected = _expected_path(reference)
    if expected is None:
        return None
    for path, saved_kind in con.execute('SELECT path,kind FROM files WHERE uid=? AND kind=?', (uid, kind)):
        if _same_path(expected, path):
            return path, saved_kind
    return _signed_authorization(uid, reference, kind)


def _persistent_reference(uid, reference, path, kind):
    # Upgrade old grants, too: the signed full path survives loss of the SQLite
    # index, while the key stays outside all integration installation folders.
    persistent = signed_reference(uid, path, kind)
    if persistent == reference:
        return reference
    _save(uid, persistent, path, kind)
    return persistent


def _authorized_legacy_project_path(con, uid, reference, kind, project_id):
    """Recover name-only links from this UID's already-approved project paths.

    The project ID must be a complete directory component prefix, not a
    substring. A repeated leaf name (e.g. Documentos) alone grants nothing.
    Full paths are never redirected to another path by this recovery.
    """
    if _expected_path(reference) is not None or not isinstance(project_id, str):
        return None
    project_id = project_id.strip()
    if not re.fullmatch(r'[0-9]{1,20}', project_id):
        return None
    _, label = parse_reference(reference, uid)
    project_component = re.compile(r'^' + re.escape(project_id) + r'(?:\s*[-_.]|\s+|$)')
    matches = {}
    for path, saved_kind in con.execute('SELECT path,kind FROM files WHERE uid=? AND kind=?', (uid, kind)):
        parts = PureWindowsPath(path)
        if ntpath.normcase(parts.name) != ntpath.normcase(label):
            continue
        directories = parts.parts if kind == 'folder' else parts.parent.parts
        if not any(project_component.match(part) for part in directories):
            continue
        matches[ntpath.normcase(str(parts)).rstrip('\\/')] = (path, saved_kind)
    if len(matches) > 1:
        raise ValueError('Há mais de um caminho autorizado para este projeto com esse nome. Confira o vínculo no editor; nenhum caminho foi escolhido automaticamente.')
    return next(iter(matches.values()), None)


def execute(uid, body, verified_user=None):
    if os.name != 'nt':
        raise ValueError('A abertura local está disponível no Windows.')
    action = body.get('action')
    if action not in SUPPORTED_ACTIONS:
        raise ValueError('Ação local inválida.')
    reference = body.get('reference')
    editor = action in {'excel-editor-read', 'excel-editor-write', 'excel-editor-preview', 'excel-editor-sheets'}
    moving = action in {'project-move-prepare', 'project-move-commit'}
    if editor or moving:
        from local_edesk.excel_editor import allowed
        if not verified_user or verified_user.get('sub') != uid or not allowed(verified_user):
            raise PermissionError('Recurso em teste disponível apenas para a conta autorizada.')
    if moving:
        import sys
        from local_edesk.project_archive import execute as move_project
        return move_project(sys.modules[__name__], uid, body)
    if action in {'authorize', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'excel-editor-preview', 'excel-editor-sheets'}:
        if not isinstance(reference, str):
            raise ValueError('Selecione um arquivo ou pasta no editor.')
        kind, expected_name = parse_reference(reference, uid)
        if (action == 'preview' or editor) and kind != 'file':
            raise ValueError('Selecione a planilha do trabalho, não a pasta.')
        with _connection() as con:
            project_recovered = False
            record = con.execute('SELECT path,kind FROM files WHERE uid=? AND reference=?', (uid, reference)).fetchone()
            expected = _expected_path(reference)
            conflicting = bool(record and (record[1] != kind or expected is not None and not _same_path(expected, record[0])))
            # Only explicit authorization can repair a conflicting local alias.
            # The full path must still match the reference and be selected in
            # Windows, or already authorized for this same UID.
            if conflicting and action == 'authorize' and expected is not None:
                record = None
            recovered = record is None
            if recovered:
                record = _authorized_path(con, uid, reference, kind)
                if record is None:
                    record = _authorized_legacy_project_path(con, uid, reference, kind, body.get('projectId'))
                    project_recovered = record is not None
        if record:
            path = _validate(record[0], kind)
            if record[1] != kind:
                raise ValueError('O tipo do vínculo local não corresponde ao arquivo ou pasta.')
            _check_expected_path(reference, path)
            # Do not attach a potentially shared legacy alias to one project.
            # _persistent_reference below saves the signed full-path identity.
            if recovered and not project_recovered:
                _save(uid, reference, path, kind, repair=action == 'authorize' and conflicting)
        elif action == 'read' or editor:
            raise ValueError('Selecione novamente o arquivo no editor deste computador.')
        else:
            if not picker_lock.acquire(blocking=False):
                raise ValueError('Conclua a seleção de arquivo ou pasta que já está aberta.')
            try:
                selected = choose(kind, f'Localize {expected or expected_name} — vínculo deste computador')
                if not selected:
                    return {'cancelled': True}
                path = _validate(selected, kind)
                _check_expected_path(reference, path)
                if (path.name or path.anchor).casefold() != expected_name.casefold():
                    raise ValueError('O nome selecionado é diferente do vínculo. Altere o arquivo ou pasta no editor.')
                _save(uid, reference, path, kind, repair=action == 'authorize' and conflicting)
            finally:
                picker_lock.release()
        persistent = _persistent_reference(uid, reference, path, kind)
        if action == 'authorize':
            return {'authorized': True, 'reference': persistent}
        if editor:
            from local_edesk.excel_editor import edit
            return {**edit(path, body), 'reference': persistent}
        if action == 'open':
            os.startfile(str(path))
            return {'opened': True, 'reference': persistent}
        if action == 'preview':
            from local_edesk.excel_mirror import render
            return {**render(path, body.get('range', '')), 'reference': persistent}
        if kind != 'file' or path.stat().st_size > 25 * 1024 * 1024:
            raise ValueError('Selecione um arquivo de até 25 MB para a prévia.')
        return {'base64': base64.b64encode(path.read_bytes()).decode('ascii'), 'reference': persistent}
    kind = 'file' if action == 'pick-file' else 'folder'
    name = body.get('name', '')
    if action == 'create-folder' and (not isinstance(name, str) or not name.strip()):
        raise ValueError('Informe o nome da pasta.')
    if not picker_lock.acquire(blocking=False):
        raise ValueError('Conclua a seleção de arquivo ou pasta que já está aberta.')
    try:
        selected = choose(kind, 'Selecione o arquivo original' if kind == 'file' else
            'Escolha onde criar a pasta' if action == 'create-folder' else 'Selecione a pasta do projeto')
        if not selected:
            return {'cancelled': True}
        path = _validate(selected, kind)
        if action == 'create-folder':
            name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '-', name).strip().rstrip('. ')[:180]
            if not name or name in {'.', '..'}:
                raise ValueError('Nome de pasta inválido.')
            path = path / name
            path.mkdir(exist_ok=True)
            path = _validate(path, kind)
        # Persist the selected full path as display/identity metadata. It is
        # never trusted as permission to open a path without native selection.
        reference = signed_reference(uid, path, kind)
        _save(uid, reference, path, kind)
        return {'reference': reference}
    finally:
        picker_lock.release()


def _save(uid, reference, path, kind, repair=False):
    _check_expected_path(reference, path)
    with _connection() as con:
        con.execute('INSERT OR IGNORE INTO files VALUES(?,?,?,?)', (uid, reference, str(path), kind))
        existing = con.execute('SELECT path,kind FROM files WHERE uid=? AND reference=?', (uid, reference)).fetchone()
        if existing[1] != kind or not _same_path(existing[0], path):
            if repair and _expected_path(reference) is not None:
                con.execute('UPDATE files SET path=?,kind=? WHERE uid=? AND reference=?', (str(path), kind, uid, reference))
                return
            raise ValueError('Este vínculo já pertence a outra pasta ou planilha. Faça uma nova seleção no editor do trabalho.')
