# EMancipate

**Free your ProtoArc EM11 Pro.** Reclaim the side buttons from the firmware's hard-coded keystrokes and bind them however you like.

_by Anarkissed_

Open-source tools for the **ProtoArc EM11 Pro** wireless mouse on macOS:

1. **A local WebHID configurator** (`web/index.html`) that reconfigures the side
   buttons directly, without the official website — including making them emit
   clean **raw mouse buttons 4 & 5** instead of the firmware's hard-coded
   `⌘[` / `⌘]` keystrokes.
2. **MouseTool** (`app/`) — a native macOS menu-bar app that remaps mouse buttons,
   scroll gestures, and keys, with **per-application** rule sets.
3. **The reverse-engineered HID protocol** (`docs/PROTOCOL.md`) — the part no one
   else has published.
4. **Diagnostic tools** (`tools/`) — a global event logger and an IOKit probe used
   during the reverse-engineering.

> ⚠️ Unofficial and unaffiliated with ProtoArc. Provided as-is. Reconfiguring
> button modes writes to the mouse's onboard memory; it's reversible (re-run the
> tool or the official site) but you do so at your own risk.

## Why this exists

The EM11 Pro's back/forward buttons ship wired to `⌘[` / `⌘]` **keystrokes**, with
the modifier baked in — which makes them ambiguous and hard to remap. The official
configurator is web-only, flaky, and offers no clean "just send a normal mouse
button" option. This toolkit fixes that: flip the side buttons to **native mouse
buttons 4/5** (which carry no baked-in modifier), then bind them however you like.

## Quick start — fix the side buttons (2 minutes)

1. Plug in the **2.4 GHz USB receiver** (Bluetooth won't work for config).
2. Quit anything that grabs HID devices (e.g. **Karabiner-Elements**).
3. Open `web/index.html` in **Chrome / Edge / Brave / Opera** (WebHID isn't in Safari/Firefox).
4. Click **Connect mouse**, choose the ProtoArc.
5. Click **“Quick: Back & Forward → raw mouse buttons.”**

Your side buttons now emit mouse buttons 4 & 5. Browsers and Finder treat those as
Back/Forward automatically; any remapper can bind them freely.

The page also lets you set any button individually (raw back, raw forward, disabled).

## MouseTool app (optional, macOS)

A native menu-bar remapper that pairs well with the raw-button setup:

- Per-app tabs — different rules per application, with an **All Apps** fallback.
- Triggers: mouse buttons (incl. 4/5), scroll up/down/left/right, and keys, each
  with `⌘ ⇧ ⌃ ⌥` modifiers.
- Actions: any keyboard shortcut, Mission Control, Show Desktop, media seek.
- Defaults: `⌘`+Back → Undo, `⌘`+Forward → Redo, `⇧`+Back → `⌘Tab`, etc.; plain
  Back/Forward pass through to native navigation.
- Launch at login; lives in the menu bar.

See [`app/README.md`](app/README.md) to build it in Xcode.

### Install the prebuilt app

Grab `MouseTool.dmg` from the [**Releases**](../../releases) page, open it, and drag
**MouseTool** into Applications.

> **First launch — Gatekeeper.** The app is **unsigned and not notarized** (no paid
> Apple Developer account), so macOS will refuse to open it on the first try.
> **Right-click the app → Open**, then confirm — you only do this once. If macOS
> still blocks it, go to **System Settings → Privacy & Security**, scroll down, and
> click **Open Anyway**.
>
> On first run it asks for **Accessibility** (and possibly **Input Monitoring**)
> under System Settings → Privacy & Security — required for the global remapping to
> work. Grant it and relaunch.

Prefer not to trust a random unsigned binary? **Build it yourself from source** —
it's a single Swift file, instructions in [`app/README.md`](app/README.md).

## Repository layout

```
web/index.html        Local WebHID configurator (no build needed)
app/MouseTool.swift    Native macOS menu-bar remapper (single-file SwiftUI)
app/assets/            App icon + menu-bar template icon (SVG + PNG)
tools/eventlog.swift   Global key/mouse-button logger (diagnostic)
tools/mousehid.swift   IOKit HID probe used during reverse-engineering
docs/PROTOCOL.md       The reverse-engineered configuration protocol
```

## Compatibility

Developed and tested on an EM11 Pro over the 2.4 GHz dongle, on Apple-silicon
macOS.

_Tested on: macOS (Apple silicon), EM11 Pro, 2.4 GHz receiver, June 2026._

Other ProtoArc models on the same firmware *may* work — the protocol doc
explains how to verify. Reports welcome via issues.

## Credits & license

Reverse-engineered from WebHID capture of the official configurator. Released under
the MIT License (see [`LICENSE`](LICENSE)). Not affiliated with or endorsed by ProtoArc.

Made with spite and solder by **Anarkissed**.
