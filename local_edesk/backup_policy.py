"""Bounded workbook backups and cleanup confined to a confirmed archive root."""
import os
from pathlib import Path
import re
import stat

BACKUP_DIRECTORY = '.gerenciador-backups'
BACKUP_LIMIT = 5
_NAME = re.compile(r'^.+-\d{8}-\d{6}-[0-9a-f]{8}\.(?:xlsm|xlsx|xls)$', re.I)


def _regular(path):
    info = path.lstat()
    return stat.S_ISREG(info.st_mode) and not path.is_symlink() and not (
        getattr(info, 'st_file_attributes', 0) & 0x400
        and getattr(info, 'st_reparse_tag', 0) & 0xFFFF0FFF != 0x9000001A)


def prune_workbook_backups(workbook, latest_backup=None):
    """Keep five generated backups of this exact filename; never touch peers."""
    workbook = Path(workbook).resolve(strict=True)
    directory = workbook.parent / BACKUP_DIRECTORY
    try:
        if directory.resolve(strict=True) != directory or directory.is_symlink():
            raise ValueError('A pasta de backups aponta para outro local.')
        pattern = re.compile(r'^' + re.escape(workbook.stem)
            + r'-(\d{8}-\d{6})-[0-9a-f]{8}' + re.escape(workbook.suffix) + r'$', re.I)
        backups = []
        for path in directory.iterdir():
            match = pattern.fullmatch(path.name)
            if match and _regular(path):
                info = path.stat()
                created = getattr(info, 'st_birthtime_ns', info.st_ctime_ns)
                backups.append((path == latest_backup, match[1], created, path.name, path))
        for _, _, _, _, path in sorted(backups, reverse=True)[BACKUP_LIMIT:]:
            path.unlink()
        return None
    except (OSError, ValueError) as error:
        return f'Planilha salva, mas a limpeza dos backups ficou pendente: {error}'


def remove_archived_backups(root):
    """Delete only generated backup files below the validated moved directory.

    No recursive delete, no link traversal, no deletion of unrecognized content.
    Failures are reported for retry; the physical project move remains recorded.
    """
    from local_edesk.project_archive import _unsafe_reparse
    root = Path(root)
    warnings = []
    removed = 0
    if root.resolve(strict=True) != root or root.is_symlink() or _unsafe_reparse(root.lstat()):
        raise ValueError('O destino mudou antes da limpeza dos backups.')

    def unreadable(error):
        warnings.append(str(error))

    for current, dirs, _ in os.walk(root, followlinks=False, onerror=unreadable):
        for name in list(dirs):
            directory = Path(current) / name
            if directory.is_symlink() or _unsafe_reparse(directory.lstat()):
                dirs.remove(name)
                warnings.append(f'Atalho ignorado: {directory}')
                continue
            if name != BACKUP_DIRECTORY:
                continue
            dirs.remove(name)
            try:
                if directory.resolve(strict=True) != directory or not directory.is_relative_to(root):
                    raise ValueError('Pasta de backups fora do projeto.')
                for path in directory.iterdir():
                    if not _NAME.fullmatch(path.name) or not _regular(path):
                        warnings.append(f'Conteúdo não reconhecido preservado: {path}')
                        continue
                    path.unlink()
                    removed += 1
                if not any(directory.iterdir()):
                    directory.rmdir()
            except (OSError, ValueError) as error:
                warnings.append(f'{directory}: {error}')
    return {'removed': removed, 'warnings': warnings, 'complete': not warnings}
