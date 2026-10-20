"""Confirmed same-volume directory moves with durable, account-scoped recovery."""
import hashlib
import json
import os
from pathlib import Path
import stat
import threading
import uuid

LOCK = threading.Lock()


def _unsafe_reparse(info):
    if not getattr(info, 'st_file_attributes', 0) & 0x400:
        return False
    # Microsoft Cloud Files tags (OneDrive) are storage placeholders, not
    # symlinks/junctions. Keep rejecting name-surrogate and unknown tags.
    # https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/c8e77b37-3909-4fe6-a4ea-2b9d423b1ee4
    tag = getattr(info, 'st_reparse_tag', 0)
    return tag & 0xFFFF0FFF != 0x9000001A


def _manifest(folder, version=2):
    result = []
    def unreadable(error):
        raise ValueError('Não foi possível conferir uma subpasta. Verifique as permissões e a disponibilidade dos arquivos no OneDrive antes de mover.') from error
    for root, dirs, files in os.walk(folder, followlinks=False, onerror=unreadable):
        for name in sorted(dirs + files):
            path = Path(root) / name
            info = path.lstat()
            if path.is_symlink() or _unsafe_reparse(info):
                raise ValueError('A pasta contém um atalho de diretório/junção. Revise antes de mover.')
            if not stat.S_ISDIR(info.st_mode) and not stat.S_ISREG(info.st_mode):
                raise ValueError('A pasta contém um item especial que não pode ser movido.')
            directory = stat.S_ISDIR(info.st_mode)
            result.append((str(path.relative_to(folder)), directory,
                0 if directory and version >= 2 else info.st_size,
                0 if directory and version >= 2 else info.st_mtime_ns))
    return hashlib.sha256(json.dumps(sorted(result)).encode()).hexdigest()


def _record(files, con, uid, reference, kind):
    if not isinstance(reference, str):
        raise ValueError('Selecione a pasta do projeto e a pasta de destino neste computador.')
    actual_kind, _ = files.parse_reference(reference, uid)
    row = con.execute('SELECT path,kind FROM files WHERE uid=? AND reference=?', (uid, reference)).fetchone()
    if row is None:
        row = files._authorized_path(con, uid, reference, kind)
    if not row or actual_kind != kind or row[1] != kind:
        raise ValueError('Selecione novamente a pasta/planilha no editor deste computador.')
    files._check_expected_path(reference, row[0])
    return Path(row[0]).resolve()


def _table(con):
    con.execute('CREATE TABLE IF NOT EXISTS project_moves(uid TEXT, operation TEXT, source_reference TEXT, '
                'destination_reference TEXT, excel_reference TEXT, plan TEXT, state TEXT, result TEXT, '
                'PRIMARY KEY(uid,operation))')


def _reference(uid, path, kind):
    from urllib.parse import quote
    identity = uuid.uuid5(uuid.NAMESPACE_URL, f'{uid}/{kind}/{path.as_posix().casefold()}')
    return f'desktop-{kind}://local/{quote(uid, safe="")}/{identity}/{quote(str(path), safe="")}'


def execute(files, uid, body):
    if not LOCK.acquire(blocking=False):
        raise ValueError('Aguarde a movimentação da pasta em andamento.')
    from local_edesk.excel_editor import lock as excel_lock
    acquired = excel_lock.acquire(blocking=False)
    try:
        if not acquired:
            raise ValueError('Aguarde a leitura ou gravação da planilha antes de mover a pasta.')
        return _execute(files, uid, body)
    finally:
        if acquired:
            excel_lock.release()
        LOCK.release()


def _execute(files, uid, body):
    with files._connection() as con:
        _table(con)
        if body['action'] == 'project-move-prepare':
            source_ref, destination_ref = body.get('reference'), body.get('destination')
            excel_ref = body.get('excelReference') or ''
            approved_parent = _record(files, con, uid, destination_ref, 'folder')
            # Recover a completed/interrupted operation before validating the old path.
            candidates = con.execute('SELECT operation,plan,state,result FROM project_moves WHERE uid=? '
                'AND source_reference=? AND excel_reference=? '
                'AND state IN ("moving","moved") ORDER BY rowid DESC LIMIT 1',
                (uid, source_ref, excel_ref)).fetchall()
            previous = next((row for row in candidates if files._same_path(json.loads(row[1])['parent'], approved_parent)), None)
            if previous:
                plan = json.loads(previous[1])
                if Path(plan['source']).exists() and not (previous[2] == 'moving' and not Path(plan['target']).exists()):
                    raise ValueError('Existe uma movimentação anterior para esta pasta e a origem voltou a existir. Confira as duas pastas antes de continuar.')
                if not Path(plan['target']).is_dir():
                    raise ValueError('O destino da movimentação anterior não foi encontrado. Confira a pasta antes de recuperar os vínculos.')
                return {**plan, 'operation': previous[0], 'alreadyMoved': previous[2] == 'moved'}
            linked_folder = _record(files, con, uid, source_ref, 'folder')
            root_ref = body.get('sourceReference') or source_ref
            source = _record(files, con, uid, root_ref, 'folder')
            if source != linked_folder and not (linked_folder.name.casefold() == 'documentos' and source == linked_folder.parent):
                raise ValueError('Selecione a pasta vinculada ou a pasta principal imediatamente acima dela. Não selecione Clientes ou outra pasta geral.')
            parent = approved_parent
            source = files._validate(source, 'folder')
            parent = files._validate(parent, 'folder')
            target = parent / source.name
            protected = {Path.home().resolve(), Path(__file__).resolve().parents[1], files.DB_PATH.resolve().parent}
            system = [Path(os.environ[name]).resolve() for name in ('SystemRoot', 'ProgramFiles', 'ProgramFiles(x86)') if os.environ.get(name)]
            if source == Path(source.anchor) or source in protected or any(p.is_relative_to(source) for p in protected) or any(source.is_relative_to(p) for p in system):
                raise ValueError('Selecione somente a pasta deste projeto, não uma pasta de sistema ou da integração.')
            if parent.is_relative_to(source) or source == target or target.exists():
                raise ValueError('O destino deve ficar fora da pasta atual e não pode conter outra pasta com o mesmo nome.')
            if source.stat().st_dev != parent.stat().st_dev:
                raise ValueError('Nesta versão, escolha um destino na mesma unidade/disco da pasta atual. Não é feita cópia com exclusão entre unidades.')
            excel = _record(files, con, uid, excel_ref, 'file') if excel_ref else None
            if excel is not None:
                files._validate(excel, 'file')
            plan = {'source': str(source), 'target': str(target), 'parent': str(parent),
                    'manifest': _manifest(source), 'manifestVersion': 2, 'excelInside': excel is not None and excel.is_relative_to(source),
                    'excelPath': str(excel) if excel else '',
                    'linkedFolderPath': str(linked_folder),
                    'oldFolderReference': source_ref, 'oldExcelReference': excel_ref}
            operation = str(uuid.uuid4())
            con.execute('INSERT INTO project_moves VALUES(?,?,?,?,?,?,?,?)',
                (uid, operation, source_ref, destination_ref, excel_ref, json.dumps(plan), 'prepared', None))
            return {**plan, 'operation': operation, 'alreadyMoved': False}

        operation = body.get('operation')
        row = con.execute('SELECT plan,state,result FROM project_moves WHERE uid=? AND operation=?', (uid, operation)).fetchone()
        if not row:
            raise ValueError('Prepare e confirme a movimentação novamente.')
        plan, state = json.loads(row[0]), row[1]
        if state == 'moved':
            if Path(plan['source']).exists() or not Path(plan['target']).is_dir():
                raise ValueError('As pastas mudaram após a movimentação. Confira os caminhos antes de atualizar os vínculos.')
            return json.loads(row[2])
        source, target, parent = (Path(plan[k]) for k in ('source', 'target', 'parent'))
        # Paths were resolved from native authorizations and retained server-side.
        if target.parent != parent or parent.is_relative_to(source) or source == target:
            raise ValueError('Plano de movimentação inválido.')
        if source.exists():
            if target.exists() or parent.resolve(strict=True) != parent or source.resolve(strict=True) != source:
                raise ValueError('O destino/origem mudou ou já existe. Prepare a movimentação novamente.')
            if _manifest(source, plan.get('manifestVersion', 1)) != plan['manifest']:
                raise ValueError('Os arquivos mudaram após a conferência. Prepare novamente antes de mover.')
            con.execute('UPDATE project_moves SET state="moving" WHERE uid=? AND operation=?', (uid, operation))
            con.commit()  # Survives interruption between filesystem and database updates.
            try:
                os.rename(source, target)  # Windows: atomic same-volume rename, no overwrite.
            except OSError as error:
                raise ValueError('Não foi possível mover. Feche a planilha e os arquivos abertos, confira as permissões e tente novamente. A operação não exclui arquivos.') from error
        elif state != 'moving':
            raise ValueError('A pasta de origem não foi encontrada. Confira os caminhos antes de continuar.')
        if not target.is_dir() or _manifest(target, plan.get('manifestVersion', 1)) != plan['manifest']:
            raise ValueError('Não foi possível conferir o destino. Verifique a pasta antes de atualizar os vínculos.')
        linked_target = target / Path(plan.get('linkedFolderPath', plan['source'])).relative_to(source)
        folder_ref = _reference(uid, linked_target, 'folder')
        excel_ref = plan['oldExcelReference']
        mappings = []
        # Preserve other projects' authorizations; create new identities for moved paths.
        for reference, path, kind in con.execute('SELECT reference,path,kind FROM files WHERE uid=?', (uid,)).fetchall():
            approved = Path(path)
            if approved.is_relative_to(source):
                new_path = target / approved.relative_to(source)
                new_ref = _reference(uid, new_path, kind)
                mappings.append((uid, new_ref, str(new_path), kind))
        mappings.append((uid, folder_ref, str(linked_target), 'folder'))
        if plan['excelInside']:
            new_excel = target / Path(plan['excelPath']).relative_to(source)
            excel_ref = _reference(uid, new_excel, 'file')
            mappings.append((uid, excel_ref, str(new_excel), 'file'))
        con.executemany('INSERT OR IGNORE INTO files VALUES(?,?,?,?)', mappings)
        result = {**plan, 'operation': operation, 'moved': True, 'folderReference': folder_ref,
                  'excelReference': excel_ref}
        con.execute('UPDATE project_moves SET state="moved",result=? WHERE uid=? AND operation=?',
                    (json.dumps(result), uid, operation))
        return result
