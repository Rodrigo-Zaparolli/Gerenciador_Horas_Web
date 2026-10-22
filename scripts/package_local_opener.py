"""Portable Windows runtime + explicit source/dependency allowlist; no app data."""
import importlib.metadata as metadata
import sys
import zipfile
from pathlib import Path
from packaging.requirements import Requirement

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'python'
SITE = RUNTIME / 'Lib' / 'site-packages'
OUT = ROOT / 'web' / 'downloads' / 'abertura-local-windows.zip'


def package(complete=False):
    files = {}
    def add(source, target):
        if source.is_file() and source.suffix != '.pyc' and '__pycache__' not in source.parts:
            files[target] = source
    for name in ['python.exe', 'python3.dll', 'python314.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'LICENSE.txt']:
        add(RUNTIME / name, 'python/' + name)
    for folder in ['DLLs', 'tcl']:
        for source in (RUNTIME / folder).rglob('*'):
            add(source, 'python/' + source.relative_to(RUNTIME).as_posix())
    for source in (RUNTIME / 'Lib').rglob('*'):
        relative = source.relative_to(RUNTIME / 'Lib')
        if relative.parts[0].removesuffix('.py') in sys.stdlib_module_names:
            add(source, 'python/Lib/' + relative.as_posix())
    queue = ['Flask', 'google-auth', 'CacheControl', 'requests', 'waitress', 'pywin32', 'Pillow']
    if complete:
        queue.append('playwright')
    seen = set()
    while queue:
        name = queue.pop()
        distribution = metadata.distribution(name)
        normalized = distribution.metadata['Name'].lower().replace('_', '-')
        if normalized in seen:
            continue
        seen.add(normalized)
        for requirement in distribution.requires or []:
            dependency = Requirement(requirement)
            if dependency.marker is None or any(dependency.marker.evaluate({'extra': extra}) for extra in ['', 'requests']):
                queue.append(dependency.name)
        for item in distribution.files or []:
            source = Path(distribution.locate_file(item)).resolve()
            if source.is_relative_to(SITE.resolve()):
                add(source, 'python/Lib/site-packages/' + source.relative_to(SITE.resolve()).as_posix())
    for name in ['local_edesk/files_server.py', 'local_edesk/local_files.py', 'local_edesk/authentication.py', 'local_edesk/excel_mirror.py', 'local_edesk/excel_editor.py', 'local_edesk/project_archive.py', 'local_edesk/backup_policy.py', 'edesk_bot/excel_preview.py',
                 'scripts/start_local_files.ps1', 'scripts/stop_local_files.ps1', 'scripts/migrate_integration_data.py']:
        add(ROOT / name, name)
    if complete:
        for name in ['local_edesk/server.py', 'local_edesk/central.py', 'local_edesk/journal.py',
                     'cloud_run/main.py', 'edesk_bot/config.py', 'edesk_bot/send_progress.py', 'edesk_bot/work_selection.py',
                     'edesk_bot/edesk_horas.py', 'edesk_bot/hour_receipt.py', 'edesk_bot/edesk_conferencia.py', 'edesk_bot/comment_percentage.py', 'edesk_bot/phase_confirmation.py', 'edesk_bot/edesk_comentario.py', 'edesk_bot/edesk_percentual.py', 'edesk_bot/edesk_fases.py',
                     'scripts/start_edesk_local.ps1', 'scripts/stop_edesk_local.ps1',
                     'scripts/start_full_integration.ps1', 'scripts/migrate_integration_data.py',
                     'scripts/integration_autostart.ps1', 'scripts/start_integration_background.ps1']:
            add(ROOT / name, name)
        for source in (RUNTIME / 'ms-playwright' / 'chromium-1187').rglob('*'):
            add(source, 'python/' + source.relative_to(RUNTIME).as_posix())
    output_path = OUT if not complete else OUT.with_name('integracao-edesk-completa-windows-v2.zip')
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for target, source in sorted(files.items()):
            archive.write(source, target)
        archive.writestr('local_edesk/__init__.py', '')
        if complete:
            archive.writestr('cloud_run/__init__.py', '')
            archive.writestr('edesk_bot/__init__.py', '')
            for name, script in [('Iniciar integração E-Desk.cmd', 'start_full_integration.ps1'),
                                 ('Parar integração E-Desk.cmd', 'stop_edesk_local.ps1')]:
                archive.writestr(name, '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\' + script + '"\r\npause\r\n')
            for name, arguments in [('Ativar inicio automatico.cmd', ''), ('Desativar inicio automatico.cmd', ' -Disable')]:
                archive.writestr(name, '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\integration_autostart.ps1"' + arguments + '\r\npause\r\n')
            archive.writestr('LEIA-ME.txt', (
                'INTEGRACAO E-DESK COMPLETA - WINDOWS 64 BITS\r\n\r\n'
                '1. Use Extrair tudo para colocar o pacote em uma pasta permanente.\r\n'
                '2. Execute Iniciar integracao E-Desk.cmd (o arquivo com esse nome na pasta extraida).\r\n'
                '3. Na pagina aberta, verifique a conexao e permita o acesso local se solicitado.\r\n'
                '4. Volte ao app e atualize com Ctrl + F5.\r\n\r\n'
                'Inclui Python, navegador e o script de horas fornecido. Nao precisa instalar Python.\r\n'
                'Tambem abre pastas, planilhas e o espelho do Excel (Excel instalado necessario para o espelho).\r\n'
                'Substitui a abertura local simples automaticamente, sem apagar a pasta antiga.\r\n'
                'Ao executar Iniciar integracao E-Desk.cmd, o inicio automatico e ativado para este usuario.\r\n'
                'Nas proximas entradas no Windows, a integracao inicia em segundo plano sem abrir o navegador.\r\n'
                'Para desativar, execute Desativar inicio automatico.cmd. Para reativar, Ativar inicio automatico.cmd.\r\n'
                'Parar integracao E-Desk.cmd encerra apenas a execucao atual.\r\n'
                'Ao enviar, entre no E-Desk se o navegador da integracao solicitar login.\r\n'
                'Mantenha esta pasta para preservar a sessao e o historico deste PC.\r\n'
                'Os vinculos de pastas e planilhas ficam no perfil do Windows e sobrevivem a novas extracoes.\r\n'
                'Na primeira atualizacao para esta versao, extraia na pasta anterior sem apagar .edesk-local.\r\n'))
        else:
            write_opener_instructions(archive)
    print(f'Pacote: {output_path.name}; {output_path.stat().st_size / 1024 / 1024:.1f} MB; {len(files)} arquivos; {len(seen)} dependencias publicas.')


def write_opener_instructions(archive):
        for name, script in [('Iniciar abertura local.cmd', 'start_local_files.ps1'), ('Parar abertura local.cmd', 'stop_local_files.ps1')]:
            archive.writestr(name, '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\' + script + '"\r\npause\r\n')
        archive.writestr('LEIA-ME.txt', ('ABERTURA LOCAL - WINDOWS 64 BITS\r\n\r\n'
            '1. Extraia todo o ZIP para uma pasta deste computador. Nao execute dentro do ZIP.\r\n'
            '2. Execute Iniciar abertura local.cmd. Pode fechar a janela depois da confirmacao.\r\n'
            '3. No navegador, permita o acesso local na pagina que sera aberta.\r\n'
            '4. Volte ao app e atualize com Ctrl + F5.\r\n'
            '5. Se solicitado, localize a pasta ou planilha original uma vez.\r\n\r\n'
            'Apos reiniciar o Windows, execute Iniciar abertura local.cmd novamente.\r\n'
            'Este pacote abre originais no Windows; nao envia horas ao E-Desk.\r\n'
            'Nao precisa instalar Python, compartilhar senhas ou usar PC central.\r\n'
            'Vinculos de pastas e planilhas ficam no perfil do Windows e sobrevivem a atualizacoes.\r\n'
            'Na primeira atualizacao para esta versao, extraia na pasta anterior sem apagar .edesk-local.\r\n'))


if __name__ == '__main__':
    package(complete='--complete' in sys.argv)
