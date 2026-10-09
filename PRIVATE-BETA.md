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
