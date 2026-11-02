"""Assemble separately compiled stable and personal-pilot bundles for Hosting."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent

def assemble(stable,pilot,output):
    stable=stable.resolve();pilot=pilot.resolve();output=output.resolve()
    if not output.is_relative_to((ROOT/'build').resolve()):raise ValueError('Output must stay inside build.')
    if output.exists():raise ValueError('Use a fresh output directory; existing releases are preserved.')
    records={}
    for name,folder,base in [('stable',stable,'/'),('pilot',pilot,'/piloto/')]:
        manifest=json.loads((folder/'web-release.json').read_text(encoding='utf-8'))
        compiled=(folder/'main.dart.js').read_bytes()
        if manifest['release'].encode() not in compiled:raise ValueError('Release and application differ.')
        if f'<base href="{base}">' not in (folder/'index.html').read_text(encoding='utf-8'):raise ValueError('Incorrect base href.')
        records[name]={'release':manifest['release'],'sha256':hashlib.sha256(compiled).hexdigest()}
    output.mkdir(parents=True)
    def copy(source,target,excluded):
        for item in source.iterdir():
            if item.name in excluded:continue
            destination=target/item.name
            if item.is_dir():shutil.copytree(item,destination)
            else:shutil.copy2(item,destination)
    copy(stable,output,{'piloto'})
    (output/'piloto').mkdir()
    copy(pilot,output/'piloto',{'downloads'})
    for folder in [output,output/'piloto']:
        manifest=json.loads((folder/'web-release.json').read_text(encoding='utf-8'))
        for key in ['updateUrl','completeUrl']:
            if not (output/manifest['integration'][key].lstrip('/')).is_file():raise ValueError('Installer missing.')
    (output.parent/'personal-hosting-record.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    return records

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--stable',type=Path,required=True)
    parser.add_argument('--pilot',type=Path,default=ROOT/'build/web')
    parser.add_argument('--output',type=Path,default=ROOT/'build/personal-hosting')
    args=parser.parse_args()
    print(json.dumps(assemble(args.stable,args.pilot,args.output)))
