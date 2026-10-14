#!/usr/bin/env python3
"""Prepare local ad-hoc MVP DMG + matching source. Never install or publish."""
import argparse,hashlib,importlib.util,json,os,plistlib,shutil,subprocess,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
VERSION='0.1.0';NAME='CoursePath Notch.app';PREFIX='CoursePath-Notch-'+VERSION

def run(*args):subprocess.run(args,check=True)
def git_files(root):
    return [Path(p) for p in subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root).decode().split('\0') if p]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,default=ROOT/'build/MVPRelease'/NAME)
    parser.add_argument('--packages',type=Path,required=True)
    args=parser.parse_args();app=args.app.resolve();out=ROOT/'build/MVPRelease';out.mkdir(parents=True,exist_ok=True)
    spec=importlib.util.spec_from_file_location('private_package',ROOT/'Scripts/package-private-beta.py');private=importlib.util.module_from_spec(spec);spec.loader.exec_module(private)
    private.verify(app)
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info['CFBundleShortVersionString']!=VERSION:raise ValueError('Build MVPRelease before packaging')
    adapter=out/'Adapter';run('python3',str(ROOT/'Scripts/build-release-adapter.py'),str(adapter))
    source=out/(PREFIX+'-source.tar.gz')
    manifest={'version':VERSION,'baseCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'packages':{}}
    with tarfile.open(source,'w:gz') as archive:
        for relative in git_files(ROOT):
            if any(part in {'.local','node_modules','build','.git','DerivedData'} for part in relative.parts) or relative.name.startswith('.env'):raise ValueError('Refusing private/generated source: '+str(relative))
            path=ROOT/relative
            if path.exists() or path.is_symlink():archive.add(path,arcname=PREFIX+'-source/'+str(relative),recursive=False)
        for checkout in sorted(args.packages.iterdir()):
            if not (checkout/'.git').exists():continue
            manifest['packages'][checkout.name]=subprocess.check_output(['git','rev-parse','HEAD'],cwd=checkout,text=True).strip()
            for relative in git_files(checkout):
                path=checkout/relative
                if path.exists() or path.is_symlink():archive.add(path,arcname=PREFIX+'-source/Dependencies/SwiftPackages/'+checkout.name+'/'+str(relative),recursive=False)
    manifest_path=out/'SOURCE-MANIFEST.json';manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    # Reopen to include metadata in the source archive without retaining a source staging copy.
    with tempfile.TemporaryDirectory(prefix='coursepath-source-manifest-') as temp:
        raw=Path(temp)/'source.tar'
        import gzip
        with gzip.open(source,'rb') as src,raw.open('wb') as dst:shutil.copyfileobj(src,dst)
        with tarfile.open(raw,'a') as archive:archive.add(manifest_path,arcname=PREFIX+'-source/SOURCE-MANIFEST.json')
        with raw.open('rb') as src,gzip.open(source,'wb') as dst:shutil.copyfileobj(src,dst)
    dmg=out/(PREFIX+'-arm64.dmg')
    with tempfile.TemporaryDirectory(prefix='coursepath-mvp-dmg-') as temp:
        stage=Path(temp);staged=stage/NAME;run('ditto',str(app),str(staged));resources=staged/'Contents/Resources'
        shutil.rmtree(staged/'Contents/Frameworks/MediaRemoteAdapter.framework')
        run('ditto',str(adapter/'MediaRemoteAdapter.framework'),str(staged/'Contents/Frameworks/MediaRemoteAdapter.framework'))
        shutil.copy2(adapter/'MediaRemoteAdapterTestClient',resources/'MediaRemoteAdapterTestClient')
        for file in ['LICENSE','THIRD_PARTY_LICENSES','RELEASE-MVP.md']:
            shutil.copy2(ROOT/file,stage/file);shutil.copy2(ROOT/file,resources/file)
        for checkout in sorted(args.packages.iterdir()):
            if not checkout.is_dir():continue
            for license_file in checkout.iterdir():
                if not license_file.is_file() or not license_file.name.upper().startswith(('LICENSE','LICENCE','COPYING','NOTICE')):continue
                for folder in [stage/'Licenses/SwiftPackages'/checkout.name,resources/'ThirdPartyLicenses'/checkout.name]:
                    folder.mkdir(parents=True,exist_ok=True);shutil.copy2(license_file,folder/license_file.name)
        for folder in [stage/'Licenses/MediaRemoteAdapter',resources/'ThirdPartyLicenses/MediaRemoteAdapter']:
            folder.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'Vendor/MediaRemoteAdapter/LICENSE',folder/'LICENSE')
        notice='CoursePath Notch '+VERSION+'\nModified from Boring Notch by The Bored Team. GPLv3.\nMatching source: https://github.com/alman69/CoursePath-Notch/releases/tag/notch-v'+VERSION+'\nMediaRemoteAdapter: BSD 3-Clause; pinned source included in the corresponding-source archive.\n'
        (stage/'ATTRIBUTION.txt').write_text(notice);(resources/'ATTRIBUTION.txt').write_text(notice)
        run('codesign','--force','--sign','-','--entitlements',str(ROOT/'Configurations/MVPRelease.entitlements'),str(staged))
        private.verify(staged)
        ent=subprocess.run(['codesign','-d','--entitlements',':-',str(staged)],check=True,capture_output=True).stdout
        if plistlib.loads(ent).get('com.apple.security.get-task-allow'):raise ValueError('Release debugging must be disabled')
        for binary in staged.rglob('*'):
            if binary.is_symlink() or not binary.is_file():continue
            with binary.open('rb') as file:magic=file.read(4)
            if magic not in [b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca']:continue
            run('codesign','--verify','--strict',str(binary))
            architectures=subprocess.check_output(['lipo','-archs',str(binary)],text=True)
            if 'arm64' not in architectures:raise ValueError('Apple silicon executable missing: '+str(binary))
        candidate=out/'Candidate'/NAME
        if candidate.exists():shutil.rmtree(candidate)
        run('ditto',str(staged),str(candidate));private.verify(candidate)
        os.symlink('/Applications',stage/'Applications')
        run('hdiutil','create','-ov','-format','UDZO','-volname','CoursePath Notch','-srcfolder',str(stage),str(dmg))
    run('hdiutil','verify',str(dmg))
    (out/'SHA256SUMS').write_text(''.join(digest(p)+'  '+p.name+'\n' for p in [dmg,source]))
    print('Prepared local candidate, DMG, corresponding source and checksums:',out)
if __name__=='__main__':main()
