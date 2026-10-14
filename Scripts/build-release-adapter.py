#!/usr/bin/env python3
"""Build the pinned media bridge for the Apple silicon MVP using Xcode only."""
from pathlib import Path
import plistlib,subprocess,sys
root=Path(__file__).resolve().parent.parent
source=root/'Vendor/MediaRemoteAdapter'
out=Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
framework=out/'MediaRemoteAdapter.framework'
version=framework/'Versions/A';(version/'Resources').mkdir(parents=True,exist_ok=True)
for name,target in [('Versions/Current','A'),('MediaRemoteAdapter','Versions/Current/MediaRemoteAdapter'),('Resources','Versions/Current/Resources')]:
 p=framework/name
 if not p.exists() and not p.is_symlink():p.symlink_to(target)
info={'CFBundleExecutable':'MediaRemoteAdapter','CFBundleIdentifier':'com.vandenbe.MediaRemoteAdapter','CFBundleName':'MediaRemoteAdapter','CFBundlePackageType':'FMWK','CFBundleVersion':'0.1.0','CFBundleShortVersionString':'0.1'}
(version/'Resources/Info.plist').write_bytes(plistlib.dumps(info))
sources=[str(p) for folder in ['adapter','private','utility'] for p in sorted((source/'src'/folder).glob('*.m'))]
base=['xcrun','clang','-arch','arm64','-mmacosx-version-min=15.0','-O2','-fobjc-arc','-I'+str(source/'include'),'-I'+str(source/'src')]
subprocess.run(base+['-dynamiclib','-install_name','@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter',*sources,'-framework','Foundation','-framework','AppKit','-framework','JavaScriptCore','-framework','UniformTypeIdentifiers','-o',str(version/'MediaRemoteAdapter')],check=True)
subprocess.run(base+[str(source/'src/test/main.m'),str(source/'src/test/NowPlayingTest.m'),'-I'+str(source/'src/test'),'-framework','Foundation','-framework','MediaPlayer','-o',str(out/'MediaRemoteAdapterTestClient')],check=True)
for p in [framework,out/'MediaRemoteAdapterTestClient']:subprocess.run(['codesign','--force','--sign','-',str(p)],check=True)
