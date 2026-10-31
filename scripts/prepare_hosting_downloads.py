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
    # Older redirects must point to the current installer too; otherwise an
    # existing v2/v55 redirect can lead back to an archived download.
    for item in redirects:
        match = re.fullmatch(r'/downloads/(integracao-edesk-completa-windows-v|abertura-local-windows-v|atualizacao-integracao-completa-)[0-9]+\.zip', item.get('destination', ''))
        if match and item.get('source') != '/downloads/' + match[1] + version + '.zip':
            item['destination'] = '/downloads/' + match[1] + version + '.zip'
    known = {item.get('source') for item in redirects}
    # Recent public installers may no longer be in this isolated build. Keep
    # their URLs working even when there is no obsolete ZIP to discover below.
    for previous in range(max(1, int(version) - 3), int(version)):
        for prefix in ('integracao-edesk-completa-windows-v', 'abertura-local-windows-v', 'atualizacao-integracao-completa-'):
            source = f'/downloads/{prefix}{previous}.zip'
            if source not in known:
                redirects.append({'source': source, 'destination': f'/downloads/{prefix}{version}.zip', 'type': 302})
                known.add(source)
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
