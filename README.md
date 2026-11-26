# touchbar-is-back

Professionally useless. Builds AI tools anyway.

TouchBack is a small menu-bar app that puts leftover Codex, Cursor, and Grok Bot quota on the Touch Bar as three quiet meters. It is not a general Touch Bar customizer.

## Install

Download `TouchBack-universal.zip` from the latest GitHub Actions build, unzip, and move `TouchBack.app` to Applications. The first build is ad-hoc signed; macOS may ask you to open it from Finder via Open.

After launch, a `◉` icon appears in the menu bar, and three quota strips should appear on the Touch Bar. If the strips are hidden, click the `◉` in the Control Strip, or choose Show on Touch Bar from the menu. Quota numbers also appear in the menu-bar panel.

Accessibility is not required. The first run may ask for network access. If Cursor or Grok Bot stay unavailable, macOS may also ask once for access to the existing Keychain item “Cursor Safe Storage”; choose Always Allow so later refreshes can run quietly.

## What it reads

Codex talks only to the already-installed Codex CLI (`codex app-server`, then `account/rateLimits/read`). It does not scrape ChatGPT cookies. If Codex is signed out or missing, that strip shows unavailable.

Cursor and Grok Bot have no official personal usage API. The app reads the already-logged-in Cursor session on this Mac and calls the same unofficial dashboard endpoints the Cursor app uses. Those endpoints can change or start failing; when they do, the strip shows unavailable. Session credentials stay on the machine and are never shown. The app never opens a browser login.

Newer Cursor builds store that session encrypted (`cursor-safe-storage`). The app opens the existing Keychain item “Cursor Safe Storage” (account “Cursor Key”) to read it, then discards the decrypted value after the request. It does not read the refresh token, does not write to Cursor’s database, and does not create a Keychain item of its own. If Keychain access is denied, those two strips stay unavailable.

## Touch Bar

A menu-bar extra is almost never the frontmost app, so the public Touch Bar API would hide the meters as soon as you switched away. This app uses the same undocumented Control Strip / system-modal Touch Bar entry points other Touch Bar utilities use, so the meters can stay up during normal use. Those entry points are not documented by Apple and may break after a macOS update. The menu-bar panel still works if the Touch Bar presentation is missing.

## Build a universal app

On a Mac with Xcode (or on GitHub Actions), run `./scripts/build-app.sh`. It builds arm64 and x86_64 slices and combines them with `lipo`. The workflow on `macos-15-intel` uploads `TouchBack-universal.zip`. Set a `DEVELOPER_ID_APPLICATION` repository secret to sign with Developer ID; otherwise CI applies an ad-hoc signature. Minimum macOS is 13.0. The app is meant to run on Intel Macs still on macOS 14, including 14.6.1.

MIT licensed.
