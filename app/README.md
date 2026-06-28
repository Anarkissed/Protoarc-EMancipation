# MouseTool (macOS)

_Part of EMancipate, by Anarkissed._

A single-file SwiftUI menu-bar app that remaps mouse buttons, scroll gestures,
and keys per-application. Designed to pair with side buttons set to raw mouse
buttons 4/5 via the WebHID tool in `../web`.

## Build (Xcode)

1. **File → New → Project → macOS → App.** Name it `MouseTool`, interface **SwiftUI**, language **Swift**.
2. Delete the auto-generated `app.swift` and `ContentView.swift`.
3. Add `app.swift` (this folder) to the target.
4. **Signing & Capabilities → remove the App Sandbox** capability (the global event
   tap needs it off).
5. **Assets.xcassets:**
   - **AppIcon** ← drag `assets/AppIcon_1024.png` onto the 1024 well.
   - New **Image Set** named exactly `MenuBarIcon` ← drop the three
     `assets/MenuBarIcon*.png` into 1x/2x/3x, then set **Render As: Template Image**.
6. Build & run. Grant **Accessibility** (and **Input Monitoring** if asked) in
   System Settings → Privacy & Security, then relaunch.

> Every rebuild changes the signature and resets the Accessibility grant during
> development. Once you export a Release build (stable signature), you grant once.

## Optional

- Media seek (side-wheel ◀▶) needs the `media-control` CLI:
  `brew install ungive/media-control/media-control`.

## Packaging a DMG

```
# After Product → Archive → Distribute App → Custom → Copy App → MouseTool.app
cd ~/Desktop && mkdir dmg && cp -R /path/to/MouseTool.app dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname MouseTool -srcfolder dmg -ov -format UDZO MouseTool.dmg
rm -rf dmg
```

Unsigned apps trigger Gatekeeper on other machines: right-click → Open the first time.
