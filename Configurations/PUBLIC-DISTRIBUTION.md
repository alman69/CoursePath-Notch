# Optional Developer ID signing checkpoint — deferred

The free first release uses `MVPRelease` and login Keychain; see `RELEASE-MVP.md`. Paid enrollment and this optional configuration are not required for that release.

`Debug` and `Release` retain the existing private ad-hoc signing. They are not public binaries. `PublicDistribution` is a separate, unshipped configuration for the app and XPC helper: Developer ID Application identity, Hardened Runtime, timestamping, and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. The app additionally sets `get-task-allow=false` and compiles the Data Protection Keychain implementation. Bundle identifiers and framework CodeSignOnCopy embedding are unchanged. Pairing remains disabled outside the existing Debug/local feature gates.

## Requirements before an approved public build

1. Apple Developer Program membership; register `dev.coursepath.notch` and `dev.coursepath.notch.BoringNotchXPCHelper` to the chosen team.
2. Install a **Developer ID Application** certificate plus its private key. Supply that team's ID as `COURSEPATH_DEVELOPMENT_TEAM`. No identity/team was selected or credentials accessed in this phase.
3. Obtain the appropriate Developer ID provisioning profile authorizing the app identifier and its own Keychain access group; configure it for the main app target. Use the same team/app identifier/access group on upgrades. The XPC helper has no Keychain group and must not gain credential access.
4. After approval, build/archive configuration `PublicDistribution`. Embedded MediaRemoteAdapter and other executable dependencies must be signed by the same team (CodeSignOnCopy), with helper runtime protection and no debug entitlement. Do not add `disable-library-validation`, unsigned-executable-memory, JIT or DYLD-environment exceptions to make something load.
5. Verify final artifacts using `codesign --verify --deep --strict`, `codesign -dv --verbose=4`, and `codesign -d --entitlements :-` on the app, helper, each framework and any embedded executable. Confirm matching Team IDs, runtime flags, stable designated requirements, no `get-task-allow=true`, and the expected app Keychain group. Re-test music/Perl MediaRemote bridge, XPC brightness functions, camera, calendar and Shelf under the actual signed runtime.
6. Only after separate approval, notarize/staple with Apple credentials and test Gatekeeper on a clean Mac. No signed archive, DMG, notarization submission or installer was produced here.

## Entitlement scope

- App: sandbox; network **client** for APIs/media; camera; calendars; Apple Events limited to the existing Music/Spotify integration; user-selected files read/write plus **app-scoped** bookmarks for Shelf. Public entitlements omit inherited network-server and document-scoped bookmark rights (no listener or document-relative bookmarks were found in the app implementation). The existing private entitlements are unchanged. Final dependency/runtime verification is still required.
- App identity and one Keychain access group: only `$(AppIdentifierPrefix)dev.coursepath.notch`; no shared app group, helper credential access, or iCloud synchronization.
- XPC: preserve the existing unsandboxed helper that accesses DisplayServices/CoreBrightness. No new privilege or runtime exception is added. Public runtime signing and base debug-entitlement injection are configured independently of the app.
- Frameworks: code signing only, no credential or runtime-exception entitlements. The system `/usr/bin/perl` host used by the upstream music bridge is not re-signed or modified. Compatibility with the real public signature remains a release gate.

## Keychain migration and limits

Public queries explicitly select `kSecUseDataProtectionKeychain=true` and synchronization false; insert/update request `WhenUnlockedThisDeviceOnly`. Lookup/delete select the same backend and identity but intentionally do not filter by accessibility, so existing records remain discoverable. A missing protected item can migrate from login Keychain only by writing and verifying the protected copy before removing the old one. Locked or missing-entitlement errors do not fall back or delete legacy credentials. Adapter tests cover query attributes, migration, restart, failed writes and locked/missing-entitlement reads.

An isolated real ad-hoc probe returned **-34018 (`errSecMissingEntitlement`)**. Accordingly, the private build retains the existing login Keychain backend; it does **not** meet the public device-only policy. Real protected-item migration, lock/unlock behavior, certificate upgrades/reinstall and backup non-migration cannot be certified until the signed/provisioned app is available. Never work around this by relaxing Keychain ACLs or system security. A changed ad-hoc code hash can still produce login-Keychain permission prompts.

Use a disposable development pairing for manual upgrade verification: pair the private build, quit all copies, install the approved signed test build, authorize any legacy ACL prompt yourself, verify migration/restart, lock/unlock, rebuild with the same team/group and verify retained access, then disconnect and verify device revocation. Do not uninstall/delete the old Keychain item before successful migration. Offline disconnect cannot guarantee remote revocation until a request reaches the server; use website device revocation if the app exits while offline.
