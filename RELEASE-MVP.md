# CoursePath Notch 0.1.0 — free release candidate

Based on Boring Notch by The Bored Team; the fork remains GPLv3. No publication is authorized by this document.

## Build and package

Requires Xcode 27 and the pinned Swift packages; no Apple Developer membership. First release: Apple Silicon, macOS 15+. The embedded media framework itself requires macOS 15, so the download page does not advertise macOS 14.

```sh
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration MVPRelease -destination 'platform=macOS' -derivedDataPath /private/tmp/coursepath-notch-phase2a -clonedSourcePackagesDirPath /private/tmp/coursepath-notch-phase2a/SourcePackages -disableAutomaticPackageResolution CONFIGURATION_BUILD_DIR="$PWD/build/MVPRelease" build
python3 Scripts/package-mvp.py --app 'build/MVPRelease/CoursePath Notch.app' --packages /private/tmp/coursepath-notch-phase2a/SourcePackages/checkouts
```

MVPRelease preserves local ad-hoc signing and the working runtime configuration; `get-task-allow=false`. It enables browser pairing, always uses the production preset, hides developer server/manual-token controls from Settings and search, and uses login Keychain with the existing default per-app ACL. It does not select Data Protection Keychain or request an unavailable signing-team entitlement. No broadly permissive Keychain ACL or global macOS security exception is introduced. Existing Debug/Release and the installed app remain separate.

The packager rebuilds the pinned MediaRemoteAdapter source, includes licenses/attribution, re-signs the staged outer app ad-hoc, checks every executable's signature/architecture, and produces DMG, corresponding-source archive and SHA256SUMS. It neither installs nor uploads. Publish all three assets together under `notch-v0.1.0` only after approval. The source archive includes the modified source, build/packaging scripts, pinned dependency sources and package resolution. It must be regenerated whenever source or binary changes.

## Student installation

1. Download the DMG from coursepath.dev/notch, open it and drag the app to Applications.
2. Try opening the app. If macOS blocks it as an unidentified developer/unnotarized app, open System Settings → Privacy & Security and use **Open Anyway** for CoursePath Notch, then authenticate and confirm. Do not disable Gatekeeper or remove quarantine through a terminal command. Do not override malware/damaged-app warnings. Managed Macs can prohibit this approval.
3. Open Settings → CoursePath → **Connect CoursePath**. Sign into your active CoursePath account in the browser; enter the native code and approve.
4. Credentials renew automatically and remain in login Keychain. Quit/restart preserves access. A rebuilt ad-hoc app can trigger another Keychain permission prompt; authorize the expected app yourself, or reconnect. No device-only accessibility guarantee is claimed for login Keychain.

## Approval and final verification still required

Production pairing is server-gated and has not been enabled or tested against production. After approval, the website needs `COURSEPATH_DESKTOP_PAIRING=1` and `COURSEPATH_DESKTOP_PAIRING_PRODUCTION=1`, and its frontend build needs `VITE_COURSEPATH_DESKTOP_PAIRING=1`, `VITE_COURSEPATH_DESKTOP_PAIRING_PRODUCTION=1`, and `VITE_COURSEPATH_NOTCH_DOWNLOAD=1` only after the GitHub assets exist. Use the production Clerk instance for production and its own signed webhook secret; Development keys remain local. Configure verified user.created/user.updated/user.deleted events to the existing HTTPS webhook handler. Never disable signature verification. The 60-second identity-revalidation fallback remains authoritative for missing deliveries.

Before publishing, perform the actual candidate journey with a disposable Development account: DMG install into a separate test folder, open → Connect → real Clerk sign-in → approve → synthetic approved calendar loads → quit/reopen → still connected → revoke device on website → Refresh fails. This needs the user's browser consent. Local native testing uses a separate Debug build with the local API preset and a disposable backend DB; production endpoints remain disabled. Current live browser tests were user-reported for the earlier implementation, not this exact DMG.

Free distribution does not provide Apple developer verification, notarization or a protected-Keychain migration guarantee. No paid enrollment is required for this MVP. Later Developer ID, Hardened Runtime compatibility and Data Protection migration are optional separate work; see Configurations/PUBLIC-DISTRIBUTION.md.
