# Private installation

Build Release into `build/PrivateBeta/Release` using the existing `boringNotch` Xcode scheme. Then run:

```sh
python3 Scripts/package-private-beta.py --install --dmg
open "$HOME/Applications/CoursePath Notch.app"
```

Use `--destination /Applications` to install system-wide instead. Quit CoursePath Notch before replacing its installed copy. The script verifies the app, embedded framework and XPC helper, refuses unrelated identities, stages replacement with rollback, and keeps the first replaced copy under ignored `build/PrivateBeta/Previous Installation.app`. The app is self-contained and does not require Xcode to run. The private DMG stays in `build/PrivateBeta`; do not upload it.

The bundle remains `dev.coursepath.notch`; preferences stay in that domain and manual credentials stay in Keychain service `dev.coursepath.notch.desktop` with server-specific accounts. Installation never copies, exports, resets or deletes those stores. Server selection and Remember last tab settings persist. The selected Home/Shelf/CoursePath tab remains session-only, as in the existing implementation.

Launch at Login uses Apple's existing `SMAppService.mainApp`. An already-enabled item is re-registered when the installed location changes; development builds cannot take it back. Enable the toggle from the installed app. If macOS requests approval, allow CoursePath Notch in System Settings → General → Login Items & Extensions. After moving an installation, toggle Launch at Login off/on from the installed copy if its registration could not be refreshed. This never registers original Boring Notch's different identity. A real logout/login or reboot and inspection of the launched path are required to verify startup; neither is automated.

Ad-hoc signing is for this Mac's private testing, with no Developer ID or notarization. macOS may ask again for Keychain/accessibility/camera/calendar approval when code changes. Replacement preserves stored credentials but cannot guarantee approval-free Keychain access across different ad-hoc signatures. Use macOS prompts normally; do not weaken Gatekeeper or library validation. The original Boring Notch updater remains disabled.

Manual checks: launch the installed app, test music/artwork, Shelf drag/drop, mirror, gestures, all tabs and Settings search; reconnect CoursePath as needed; close/reopen, sleep/wake and reconnect the monitor; enable login startup and reboot; verify only the installed CoursePath Notch launches. Test a replacement after quitting, then check settings and connection again. Hardware, reboot and interactive permission prompts remain unverified until performed.

# Browser authorization development checkpoint

Browser pairing and renewable credentials are implemented behind local development flags; the installed Release app retains manual-token authentication. See `../CoursePath App/DESKTOP-PAIRING.md` for the protocol, expiration policy, guards and manual setup. No real Clerk/browser callback test has run. Do not enable production pairing or treat this as a public authentication release.

The native tests include separate Keychain persistence, PKCE/state validation, concurrent renewal serialization, ambiguous-response handling, cancellation and task completion after renewal. `python3 Tests/run-local-connection-test.py --pairing` exercises real local HTTP and sandboxed Keychain integration with simulated Clerk consent and disposable data; omit the flag for the existing manual-token probe.

Website companion checkpoint: `3c2f06a` on `coursepath-notch-integration`. Native stability and installation checkpoints: `46104f5` and `1a2abc9` on `coursepath-integration`. Final automated checks: 64 native tests, 540 website tests, Debug/Release builds, website production build, and isolated manual/paired HTTP probes. Real browser consent remains unverified.

Changed native authentication files: `CoursePathAuth.swift`, `CoursePathBrowserSession.swift`, `CoursePathStore.swift`, `CoursePathAPI.swift`, `CoursePathConnectionSettings.swift`, `Info.plist`, `Package.swift`, `CoursePathAuthTests.swift`, `LocalPairingProbe.swift`, `local-backend-fixture.mjs`, `run-local-connection-test.py`, and this document. Earlier checkpoints contain the calendar/day-rollover, window/observer cleanup, weak capture, installation script/hook and their regression tests. No music, Shelf, mirror or gesture UI was redesigned.
