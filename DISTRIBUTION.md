# Distribution

Island is distributed free through GitHub Releases. It is **ad-hoc signed** (`codesign -s -`) and **not notarized** yet, because notarization requires a paid Apple Developer account. Once one is available, `scripts/notarize.sh` does it in one step (see below).

## Opening Island the first time

macOS blocks apps from unidentified developers on first launch. This is the normal, per-app way to allow one:

1. Move **Island.app** to **Applications** and double-click it. macOS says it can't verify the developer. Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to Security, find *"Island" was blocked to protect your Mac*, and click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open**.

You only do this once per version. **Don't disable Gatekeeper globally**; it isn't needed.

## Verify your download

```sh
shasum -a 256 Island.dmg   # compare with SHA256SUMS.txt from the release
codesign -dv /Applications/Island.app
```

## Permissions Island may ask for

| Prompt | When | Why |
|---|---|---|
| Automation → Music / Spotify / VLC / browser | first time that app plays | read now-playing info and send play/pause/skip |
| Calendars | only if you enable Calendar | show your next event |
| Accessibility | only if you use media keys with no supported player | send the system play/pause key |
| Downloads folder | possibly when a download finishes | show its name and offer Open / Show in Finder |
| Microphone | only if you turn on teleprompter voice follow | hear where you are in the script |
| Speech Recognition | only if you turn on teleprompter voice follow | match your words to the script, on-device |

## Building releases

`scripts/build-release.sh <version>` builds `dist/Island.app` (universal). `scripts/package-release.sh` then produces `Island.zip` (via `ditto`), `Island.dmg` and `SHA256SUMS.txt`. CI does the same on every tag `v*`.

## Updates

Each release carries `version.json` (`{"version", "build"}`). Island compares that build with its own, at most once a day, and shows "Update Available" in the menu-bar menu and in Settings › General. A release can be replaced under the same tag and still be detected. Island only links to the release page. It never downloads or installs anything itself.

## Notarizing (needs an Apple Developer account)

1. Join the Apple Developer Program. Create a **Developer ID Application** certificate and install it in your login keychain.
2. Save notary credentials once: `xcrun notarytool store-credentials island-notary --apple-id <you> --team-id <TEAMID>` (use an app-specific password).
3. Build, then notarize:
   ```sh
   scripts/build-release.sh 0.3.0
   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=island-notary scripts/notarize.sh
   ```
   This signs with the hardened runtime, notarizes the app and the DMG, staples both, and checks them with Gatekeeper. Downloads then open with no "Open Anyway" step.

