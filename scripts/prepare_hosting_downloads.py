"""Archive obsolete numbered installers from build output, preserving old URLs."""
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    downloads = ROOT / 'build/web/downloads'
    manifest = json.loads((ROOT / 'build/web/web-release.json').read_text(encoding='utf-8'))
    version = manifest['integration']['version']
    if not re.fullmatch(r'[0-9]+', version):
        raise ValueError('Invalid integration version')
    for key in ('updateUrl', 'completeUrl'):
        if not (ROOT / 'build/web' / manifest['integration'][key].lstrip('/')).is_file():
            raise ValueError('Current installer missing')
    config_path = ROOT / 'firebase.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))
    hosting = config['hosting']
    hosting = hosting[0] if isinstance(hosting, list) else hosting
    redirects = hosting.setdefault('redirects', [])
    known = {item.get('source') for item in redirects}
    archive = ROOT / 'build/hosting-download-archive'
    archive.mkdir(exist_ok=True)
    count = 0
    for package in downloads.glob('*.zip'):
        match = re.fullmatch(r'(integracao-edesk-completa-windows-v|abertura-local-windows-v|atualizacao-integracao-completa-)([0-9]+)\.zip', package.name)
        if not match or match[2] == version or (match[1] == 'integracao-edesk-completa-windows-v' and match[2] == '2'):
            continue
        if package.resolve().parent != downloads.resolve():
            raise ValueError('Installer outside build downloads')
        source = '/downloads/' + package.name
        if source not in known:
            redirects.append({'source': source, 'destination': '/downloads/' + match[1] + version + '.zip', 'type': 302})
            known.add(source)
        shutil.move(str(package), str(archive / package.name))
        count += 1
    config_path.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    print(f'OBSOLETE_BUILD_INSTALLERS_ARCHIVED: {count}; current version {version}')

if __name__ == '__main__':
    prepare()
