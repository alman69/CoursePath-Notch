"""Run a sandboxed native probe against an isolated CoursePath backend (port 5173).
No real Clerk identities, account data, provider keys, or persistent tokens are used.
"""
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import tempfile
import uuid

notch = Path(__file__).resolve().parent.parent
app = notch.parent / "CoursePath App"
with socket.socket() as check:
    check.bind(("127.0.0.1", 5173))  # Fail before launching anything if a real server owns this port.
with tempfile.TemporaryDirectory(prefix="coursepath-native-e2e-") as temporary:
    root = Path(temporary)
    bundle = root / "ConnectionProbe.app"
    executable = bundle / "Contents/MacOS/ConnectionProbe"
    executable.parent.mkdir(parents=True)
    info = {"CFBundleIdentifier": "dev.coursepath.notch.connectionprobe", "CFBundleExecutable": "ConnectionProbe",
            "CFBundlePackageType": "APPL", "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
    with (bundle / "Contents/Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    sources = [notch / "boringNotch/CoursePath" / file for file in
               ["CoursePathModels.swift", "CoursePathAPI.swift", "CoursePathKeychain.swift", "CoursePathStore.swift"]]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", os.uname().machine + "-apple-macosx14.0",
                    *map(str, sources), str(notch / "Tests/LocalConnectionProbe.swift"), "-o", str(executable)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(notch / "boringNotch/boringNotch.entitlements"), str(bundle)], check=True, capture_output=True)
    backend = subprocess.Popen(["node", str(notch / "Tests/local-backend-fixture.mjs"), str(app), str(root / "database")],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    service = "dev.coursepath.notch.e2e." + str(uuid.uuid4())
    try:
        credential = json.loads(backend.stdout.readline())
        result = subprocess.run([str(executable)], input=json.dumps({"token": credential.pop("token"), "service": service}),
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
        subprocess.run(["security", "delete-generic-password", "-s", service, "-a", "http://127.0.0.1:5173"], capture_output=True)
