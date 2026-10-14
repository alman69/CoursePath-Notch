"""Run a sandboxed native probe against an isolated backend on an ephemeral loopback port.
No real Clerk identities, account data, provider keys, or persistent tokens are used.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid
import sys
pairing = "--pairing" in sys.argv

notch = Path(__file__).resolve().parent.parent
app = notch.parent / "CoursePath App"
with tempfile.TemporaryDirectory(prefix="coursepath-native-e2e-") as temporary:
    root = Path(temporary)
    bundle = root / "ConnectionProbe.app"
    executable = bundle / "Contents/MacOS/ConnectionProbe"
    executable.parent.mkdir(parents=True)
    info = {"CFBundleIdentifier": "dev.coursepath.notch.connectionprobe", "CFBundleExecutable": "ConnectionProbe",
            "CFBundlePackageType": "APPL", "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
    with (bundle / "Contents/Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    backend = subprocess.Popen(["node", str(notch / "Tests/local-backend-fixture.mjs"), str(app), str(root / "database"), "pairing" if pairing else "manual"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    service = "dev.coursepath.notch.e2e." + str(uuid.uuid4())
    test_url = None
    try:
        credential = json.loads(backend.stdout.readline())
        test_url = "http://127.0.0.1:" + str(credential.pop("port"))
        # Only this disposable probe substitutes the local preset's port. The shipped
        # application's fixed URL presets and security policy remain unchanged.
        models = root / "CoursePathModels.swift"
        models.write_text((notch / "boringNotch/CoursePath/CoursePathModels.swift").read_text().replace(
            '"http://127.0.0.1:5173"', '"' + test_url + '"'))
        sources = [models] + [notch / "boringNotch/CoursePath" / file for file in
                   ["CoursePathAPI.swift", "CoursePathAuth.swift", "CoursePathKeychain.swift", "CoursePathCredentialLock.swift", "CoursePathStore.swift", "CoursePathTaskPresentation.swift"]]
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", os.uname().machine + "-apple-macosx14.0",
                        *map(str, sources), str(notch / ("Tests/LocalPairingProbe.swift" if pairing else "Tests/LocalConnectionProbe.swift")), "-o", str(executable)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(notch / "boringNotch/boringNotch.entitlements"), str(bundle)], check=True, capture_output=True)
        result = subprocess.run([str(executable)], input=json.dumps({**credential, "service": service}),
                                capture_output=True, text=True, timeout=30)
        print(result.stdout.strip())  # The probe emits only fixed PASS/FAIL metadata.
        if result.returncode:
            raise SystemExit("Sandboxed native probe failed; no personal data was accessed.")
    finally:
        backend.terminate()
        try:
            backend.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            backend.kill(); backend.communicate()
        if test_url:
            subprocess.run(["security", "delete-generic-password", "-s", service, "-a", test_url], capture_output=True)

            if pairing:
                subprocess.run(["security", "delete-generic-password", "-s", service + ".paired", "-a", test_url], capture_output=True)
