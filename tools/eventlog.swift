// eventlog.swift — prints every key/mouse-button event, globally. Read-only.
// Build: swiftc eventlog.swift -o eventlog
// Run:   ./eventlog        (grant Accessibility/Input Monitoring, then press buttons)
// Ctrl-C to quit.

import Foundation
import CoreGraphics

let mask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue)

func mods(_ f: CGEventFlags) -> String {
    var s = ""
    if f.contains(.maskCommand){s+="⌘"}; if f.contains(.maskShift){s+="⇧"}
    if f.contains(.maskControl){s+="⌃"}; if f.contains(.maskAlternate){s+="⌥"}
    return s.isEmpty ? "" : " mods=\(s)"
}

let cb: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .keyDown:
        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        print("KEY DOWN   keycode=\(kc)\(mods(event.flags))")
    case .flagsChanged:
        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        print("FLAGS      keycode=\(kc)\(mods(event.flags))")
    case .otherMouseDown:
        print("MOUSE BTN  button=\(event.getIntegerValueField(.mouseEventButtonNumber))\(mods(event.flags))")
    case .leftMouseDown:  print("MOUSE BTN  button=0 (left)")
    case .rightMouseDown: print("MOUSE BTN  button=1 (right)")
    default: break
    }
    return Unmanaged.passUnretained(event)   // listen only, never swallow
}

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .listenOnly, eventsOfInterest: mask, callback: cb, userInfo: nil) else {
    FileHandle.standardError.write(Data("Tap failed — grant Accessibility/Input Monitoring, then rerun.\n".utf8)); exit(1)
}
let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("Logging. Press your Back/Forward buttons now. Ctrl-C to quit.\n")
CFRunLoopRun()
