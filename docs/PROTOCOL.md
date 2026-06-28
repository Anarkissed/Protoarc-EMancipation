# ProtoArc EM11 Pro — HID configuration protocol (reverse-engineered)

_Part of [EMancipate](../README.md), by Anarkissed._

This documents the proprietary WebHID protocol the ProtoArc EM11 Pro uses to
configure its buttons in onboard memory. It was reverse-engineered by capturing
`sendReport` traffic from the official web configurator. Other ProtoArc models
(and rebadged variants on the same firmware) may share it — verify before trusting.

> **Status of findings:** confirmed by capture + live testing on an EM11 Pro over
> the 2.4 GHz USB receiver on macOS. Bluetooth was **not** used for config.

## Device identity

| Transport | VID | PID | Notes |
|---|---|---|---|
| 2.4 GHz dongle | `0x260D` | `0x1282` | Config rides the **keyboard** collection: usage page `0x0001`, usage `0x06` |
| Bluetooth | `0x3554` | `0xF819` | Not used for configuration here |

The configurable channel is the device's own keyboard collection, **not** a
separate vendor (`0xFF..`) collection. There are often multiple identical
matching interfaces; writes succeed on the keyboard one.

## Transport facts

- **WebHID only.** Raw `IOHIDDeviceSetReport` from a macOS CLI returns success but
  the device ignores it (reads come back as a static stub; writes never latch).
  The browser's WebHID path is the only one observed to actually take effect.
- Use a **Chromium browser** (Chrome/Edge/Opera/Brave) and the **2.4 GHz receiver**.
- Other software grabbing the HID device (e.g. Karabiner-Elements'
  `karabiner_grabber`) will cause `NotAllowedError: Failed to open device`. Quit it first.

## Frame format

- **Report ID:** `8`
- **Length:** 16 bytes (the report id is *not* part of these 16 — WebHID's
  `sendReport(8, payload)` prepends it)
- **Trailer checksum (byte 15):** `(0x4D - sum(bytes[0..14])) & 0xFF`

```js
function frame(bytes) {
  const b = new Uint8Array(16);
  bytes.forEach((v, i) => b[i] = v);
  let s = 0; for (let i = 0; i < 15; i++) s += b[i];
  b[15] = (0x4D - s) & 0xFF;
  return b;
}
```

## Session handshake (sent once before writes)

```
01 00 00 00 08 93 48 71 cf 00 00 00 00 00 00 29
```

Byte 4 = `08` (protocol/version), bytes 5–8 = a session nonce. Replaying the
captured nonce works, so it behaves as a client-chosen id rather than a
server challenge on this firmware.

## Button addresses & macro slots

| Button | Mode address | Macro slot |
|---|---|---|
| Right click | `0x64` | `0x20` |
| Wheel click | `0x68` | `0x40` |
| Back        | `0x6C` | `0x60` |
| Forward     | `0x70` | `0x80` |
| DPI         | `0x74` | `0xA0` |

```
slotFor(addr) = 0x20 * (((addr - 0x64) / 4) + 1)
```

## Command: set button mode  (command `07`, sub `00`)

```
07 00 00 <ADDR> 04 <T5> <T6> <T7> <INNER> 00 …
INNER = (0x55 - (T5 + T6 + T7)) & 0xFF      (then the frame trailer is appended)
```

| Behaviour | `T5 T6 T7` | Result |
|---|---|---|
| Raw mouse **Back**    | `01 08 00` | Emits **mouse button 4** ✅ |
| Raw mouse **Forward** | `01 10 00` | Emits **mouse button 5** ✅ |
| Disabled              | `00 00 00` | Button does nothing |
| Keyboard macro        | `05 00 00` | Selects the macro slot — **see warning** |

> ⚠ **Keyboard-macro mode is broken on this unit.** The mouse accepts both the
> macro-store and the mode write without error, but emits **no keystroke at all**
> (verified with a global CGEvent logger; F12/F13/F14 all produced nothing).
> Use the **raw mouse** modes instead — they emit clean buttons 4/5 that any OS
> or remapper can bind, with no baked-in modifier.

Example — set Back to raw mouse button 4:
```
07 00 00 6c 04 01 08 00 4c 00 00 00 00 00 00 <trailer>
```

## Command: store a key macro  (command `07`, sub `01`)  — *for reference; non-functional here*

```
07 00 01 <SLOT> 08 02 81 <USAGE> 00 41 <USAGE> 00 07 00 00
```

`81` = press, `41` = release, `<USAGE>` = HID keyboard usage (e.g. `0x68`=F13,
`0x69`=F14). Pair with a `05` mode write on the button's address.

## Command: read a block  (command `08`)

```
08 00 00 <ADDR> 0a …
```

The EM11 Pro did **not** answer reads reliably (returned a static stub), so this
is documented for completeness only.

## Practical recipe (what the tool in `/web` does)

1. Open the device's keyboard collection (`260D:1282`, page `0x0001`, usage `0x06`).
2. Send the session handshake.
3. For each side button, send a **set-mode** frame: Back → `01 08`, Forward → `01 10`.
4. Done — the buttons now emit raw mouse buttons 4/5, persisted in onboard memory.
