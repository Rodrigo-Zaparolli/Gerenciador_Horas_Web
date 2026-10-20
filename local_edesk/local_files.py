"""User-selected Windows paths, scoped to Firebase UID, never supplied to startfile by HTTP."""
import base64
import os
import re
import sqlite3
import threading
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
PROTOCOL_VERSION = 'persistent-file-links-5'
SPREADSHEET_LAYOUTS = ('enterprise', 'professional-maker')
PROJECT_ROOT_MOVE = True
SUPPORTED_ACTIONS = frozenset({'authorize', 'pick-file', 'pick-folder', 'create-folder', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'excel-editor-preview', 'project-move-prepare', 'project-move-commit'})


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
    return PureWindowsPath(str(first)).as_posix().rstrip('/').casefold() == PureWindowsPath(str(second)).as_posix().rstrip('/').casefold()


def _check_expected_path(reference, path):
    expected = _expected_path(reference)
    if expected is not None and not _same_path(expected, path):
        raise ValueError('A pasta ou planilha selecionada não corresponde ao caminho salvo. Selecione o destino correto no editor deste trabalho.')


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


@contextmanager
def _connection():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=10)
    try:
        with con:
            con.execute('CREATE TABLE IF NOT EXISTS files(uid TEXT, reference TEXT, path TEXT, kind TEXT, PRIMARY KEY(uid,reference))')
            _import_legacy(con)
            yield con
    finally:
        con.close()


def _import_legacy(con, source_path=None):
    """Merge authorizations from this extraction without replacing other links.

    The stable database survives extracting a new package into another folder.
    Each old database is imported once, including when the destination already
    contains links from another extraction. The original is never modified.
    """
    legacy = Path(source_path or LEGACY_DB_PATH).resolve()
    if legacy == DB_PATH.resolve() or not legacy.is_file():
        return
    con.execute('CREATE TABLE IF NOT EXISTS imported_file_databases(source TEXT PRIMARY KEY)')
    source = str(legacy)
    if con.execute('SELECT 1 FROM imported_file_databases WHERE source=?', (source,)).fetchone():
        return
    with closing(sqlite3.connect(legacy.as_uri() + '?mode=ro', uri=True, timeout=10)) as old:
        rows = old.execute('SELECT uid,reference,path,kind FROM files').fetchall()
    con.executemany('INSERT OR IGNORE INTO files(uid,reference,path,kind) VALUES(?,?,?,?)', rows)
    con.execute('INSERT OR IGNORE INTO imported_file_databases(source) VALUES(?)', (source,))


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
    return None


def _persistent_reference(uid, reference, path, kind):
    # Upgrade old browser/name-only links to an identity with the full path.
    if reference.startswith('desktop-') and _expected_path(reference) is not None:
        return reference
    identity = f'{uid}/{kind}/{PureWindowsPath(str(path)).as_posix().casefold()}'
    stable_id = uuid.uuid5(uuid.NAMESPACE_URL, identity)
    persistent = f'desktop-{kind}://local/{quote(uid, safe="")}/{stable_id}/{quote(str(path), safe="")}'
    _save(uid, persistent, path, kind)
    return persistent


def execute(uid, body, verified_user=None):
    if os.name != 'nt':
        raise ValueError('A abertura local está disponível no Windows.')
    action = body.get('action')
    if action not in SUPPORTED_ACTIONS:
        raise ValueError('Ação local inválida.')
    reference = body.get('reference')
    editor = action in {'excel-editor-read', 'excel-editor-write', 'excel-editor-preview'}
    moving = action in {'project-move-prepare', 'project-move-commit'}
    if editor or moving:
        from local_edesk.excel_editor import allowed
        if not verified_user or verified_user.get('sub') != uid or not allowed(verified_user):
            raise PermissionError('Recurso em teste disponível apenas para a conta autorizada.')
    if moving:
        import sys
        from local_edesk.project_archive import execute as move_project
        return move_project(sys.modules[__name__], uid, body)
    if action in {'authorize', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'excel-editor-preview'}:
        if not isinstance(reference, str):
            raise ValueError('Selecione um arquivo ou pasta no editor.')
        kind, expected_name = parse_reference(reference, uid)
        if (action == 'preview' or editor) and kind != 'file':
            raise ValueError('Selecione a planilha do trabalho, não a pasta.')
        with _connection() as con:
            record = con.execute('SELECT path,kind FROM files WHERE uid=? AND reference=?', (uid, reference)).fetchone()
            recovered = record is None
            if recovered:
                record = _authorized_path(con, uid, reference, kind)
        if record:
            path = _validate(record[0], kind)
            if record[1] != kind:
                raise ValueError('O tipo do vínculo local não corresponde ao arquivo ou pasta.')
            _check_expected_path(reference, path)
            if recovered:
                _save(uid, reference, path, kind)
        elif action == 'read' or editor:
            raise ValueError('Selecione novamente o arquivo no editor deste computador.')
        else:
            if not picker_lock.acquire(blocking=False):
                raise ValueError('Conclua a seleção de arquivo ou pasta que já está aberta.')
            try:
                selected = choose(kind, f'Localize {expected_name} — vínculo deste computador')
                if not selected:
                    return {'cancelled': True}
                path = _validate(selected, kind)
                _check_expected_path(reference, path)
                if (path.name or path.anchor).casefold() != expected_name.casefold():
                    raise ValueError('O nome selecionado é diferente do vínculo. Altere o arquivo ou pasta no editor.')
                _save(uid, reference, path, kind)
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
        reference = f'desktop-{kind}://local/{quote(uid, safe="")}/{uuid.uuid4()}/{quote(str(path), safe="")}'
        _save(uid, reference, path, kind)
        return {'reference': reference}
    finally:
        picker_lock.release()


def _save(uid, reference, path, kind):
    _check_expected_path(reference, path)
    with _connection() as con:
        con.execute('INSERT OR IGNORE INTO files VALUES(?,?,?,?)', (uid, reference, str(path), kind))
        existing = con.execute('SELECT path,kind FROM files WHERE uid=? AND reference=?', (uid, reference)).fetchone()
        if existing[1] != kind or not _same_path(existing[0], path):
            raise ValueError('Este vínculo já pertence a outra pasta ou planilha. Faça uma nova seleção no editor do trabalho.')
