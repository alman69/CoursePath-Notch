#!/usr/bin/env python3
"""Package an already-built, ad-hoc signed private beta. Never touches user data."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = 'CoursePath Notch.app'

def run(*args):
    subprocess.run(args, check=True)

def verify(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'dev.coursepath.notch':
        raise ValueError('Refusing an app with a different identity')
    if info.get('SUEnableAutomaticChecks') or info.get('SUAllowsAutomaticUpdates'):
        raise ValueError('Upstream updates must be disabled')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    helper = app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc'
    helper_info = plistlib.loads((helper / 'Contents/Info.plist').read_bytes())
    if helper_info['CFBundleIdentifier'] != 'dev.coursepath.notch.BoringNotchXPCHelper':
        raise ValueError('Unexpected helper identity')
    for component in [app, helper, app / 'Contents/Frameworks/MediaRemoteAdapter.framework']:
        result = subprocess.run(['codesign', '-dv', '--verbose=4', str(component)], capture_output=True, text=True, check=True)
        if 'Signature=adhoc' not in result.stderr or 'TeamIdentifier=not set' not in result.stderr:
            raise ValueError('Private components must all use local ad-hoc signing')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/PrivateBeta/Release' / APP_NAME)
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--destination', type=Path, default=Path.home() / 'Applications')
    parser.add_argument('--dmg', action='store_true')
    args = parser.parse_args()
    verify(args.app)
    if args.install:
        destination = args.destination.expanduser().resolve()
        if destination not in [Path('/Applications'), Path.home() / 'Applications']:
            parser.error('Use /Applications or ~/Applications for an everyday installation')
        destination.mkdir(parents=True, exist_ok=True)
        target = destination / APP_NAME
        # Never replace another app or a symlink; preserve the previous private build.
        if target.is_symlink():
            raise ValueError('Refusing a symlink installation')
        if target.exists():
            verify(target)
        processes = subprocess.run(['ps', '-axo', 'comm='], capture_output=True, text=True, check=True).stdout.splitlines()
        if any(line.strip().startswith(str(target) + '/Contents/MacOS/') for line in processes):
            raise ValueError('Quit the installed CoursePath Notch before replacing it')
        with tempfile.TemporaryDirectory(prefix='.coursepath-install-', dir=destination) as stage:
            replacement = Path(stage) / APP_NAME
            run('ditto', str(args.app), str(replacement))
            verify(replacement)
            backup = Path(stage) / 'previous.app'
            if target.exists():
                target.rename(backup)
            try:
                replacement.rename(target)
                verify(target)
            except BaseException:
                if target.exists():
                    target.rename(Path(stage) / 'failed.app')
                if backup.exists():
                    backup.rename(target)
                raise
            if backup.exists():
                archive = ROOT / 'build/PrivateBeta/Previous Installation.app'
                if not archive.exists():
                    run('ditto', str(backup), str(archive))
        run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', str(target))
        print('Installed:', target)
    if args.dmg:
        output = ROOT / 'build/PrivateBeta/CoursePath Notch Private Beta.dmg'
        with tempfile.TemporaryDirectory(prefix='coursepath-dmg-', dir=ROOT / 'build/PrivateBeta') as stage:
            run('ditto', str(args.app), str(Path(stage) / APP_NAME))
            os.symlink('/Applications', Path(stage) / 'Applications')
            run('hdiutil', 'create', '-ov', '-format', 'UDZO', '-volname', 'CoursePath Notch Private Beta', '-srcfolder', stage, str(output))
        run('hdiutil', 'verify', str(output))
        print('Private installer:', output)

if __name__ == '__main__':
    main()
