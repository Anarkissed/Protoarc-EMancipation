// MouseTool.swift — per-app mouse/key remapper (CGEventTap + SwiftUI)
//
// New: per-app tabs, native mouse-button triggers (buttons 3/4), and
// per-application tabs — each app gets its own rules, falling back to "All Apps".
//
// BUILD (Xcode macOS App, SwiftUI): delete auto Mouse_ToolApp.swift &
// ContentView.swift, drop this in. Target → Signing & Capabilities → remove
// App Sandbox. Run, grant Accessibility, relaunch.
// Seek needs: brew install ungive/media-control/media-control

import SwiftUI
import Combine
import AppKit
import CoreGraphics
import ApplicationServices
import UniformTypeIdentifiers
import ServiceManagement

// ───────────────────────────── Models ─────────────────────────────
enum Modifier: String, Codable, CaseIterable, Hashable {
    case cmd, shift, ctrl, opt
    var symbol: String { ["cmd":"⌘","shift":"⇧","ctrl":"⌃","opt":"⌥"][rawValue]! }
    var fullName: String { ["cmd":"Command","shift":"Shift","ctrl":"Control","opt":"Option"][rawValue]! }
    static func from(_ f: NSEvent.ModifierFlags) -> [Modifier] {
        var m: [Modifier] = []
        if f.contains(.command){m.append(.cmd)}; if f.contains(.shift){m.append(.shift)}
        if f.contains(.control){m.append(.ctrl)}; if f.contains(.option){m.append(.opt)}
        return m
    }
}
struct Trigger: Codable, Equatable, Hashable {
    var kind: String          // "button" | "key" | scrollUp/Down/Left/Right
    var button: Int?
    var keyCode: Int?
    var mods: [Modifier]
}
struct RuleAction: Codable, Equatable, Hashable {
    var type: String          // "key" | "missionControl" | "showDesktop" | "mediaSeek"
    var keyCode: Int?
    var keyMods: [Modifier]?
}
struct Rule: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger: Trigger
    var action: RuleAction?
    var app: String? = nil    // bundle id; nil = All Apps
}
struct AppRef: Codable, Equatable, Identifiable { var id: String { bundleID }; var bundleID: String; var name: String }
struct SaveData: Codable { var apps: [AppRef]; var rules: [Rule] }

// ──────────────────────── Key name <-> code ───────────────────────
let nameToCode: [String: Int] = [
    "a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,"k":40,"l":37,"m":46,
    "n":45,"o":31,"p":35,"q":12,"r":15,"s":1,"t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6,
    "0":29,"1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,
    "-":27,"minus":27,"=":24,"equal":24,"plus":24,"[":33,"]":30,"\\":42,";":41,"'":39,",":43,".":47,"/":44,"`":50,
    "space":49,"tab":48,"return":36,"enter":36,"esc":53,"escape":53,"delete":51,"backspace":51,
    "left":123,"right":124,"down":125,"up":126,"home":115,"end":119,"pageup":116,"pagedown":121,
    "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111,
    "f13":105,"f14":107,"f15":113,"f16":106,"f17":64,"f18":79,"f19":80,"f20":90
]
let specialDisplay: [Int: String] = [
    36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",123:"←",124:"→",125:"↓",126:"↑",24:"=",27:"−",33:"[",30:"]",
    122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",
    105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"
]
func codeDisplay(_ c: Int) -> String {
    if let s = specialDisplay[c] { return s }
    if let kv = nameToCode.first(where: { $0.value == c && $0.key.count == 1 }) { return kv.key.uppercased() }
    if let kv = nameToCode.first(where: { $0.value == c }) { return kv.key.capitalized }
    return "key\(c)"
}
func asModifier(_ t: String) -> Modifier? {
    switch t {
    case "⌘","cmd": return .cmd
    case "⇧": return .shift
    case "⌃","ctrl": return .ctrl
    case "⌥","opt","alt": return .opt
    default: break
    }
    if t.count >= 3 {
        if "command".hasPrefix(t) { return .cmd }
        if "shift".hasPrefix(t) { return .shift }
        if "control".hasPrefix(t) { return .ctrl }
        if "option".hasPrefix(t) { return .opt }
    }
    return nil
}
func parseShortcut(_ s: String) -> RuleAction? {
    let toks = s.split(whereSeparator: { $0 == "+" || $0 == " " }).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !toks.isEmpty else { return nil }
    var mods: [Modifier] = []; var code: Int? = nil
    for t in toks {
        if let m = asModifier(t) { mods.append(m) }
        else if let kc = nameToCode[t] { code = kc }
        else { return nil }
    }
    guard let kc = code else { return nil }
    return RuleAction(type: "key", keyCode: kc, keyMods: mods)
}
// Autocomplete vocabulary for the shortcut field.
let shortcutVocab: [String] = ["Command","Shift","Control","Option","Tab","Space","Return","Escape","Delete","Left","Right","Up","Down"] + (1...20).map { "F\($0)" }

// ──────────────────────── Descriptions ────────────────────────────
func buttonName(_ n: Int) -> String {
    switch n { case 0:"Left Click"; case 1:"Right Click"; case 2:"Middle Click"; case 3:"Back Button"; case 4:"Forward Button"; default:"Button \(n)" }
}
func triggerBase(_ t: Trigger) -> String {
    switch t.kind {
    case "button": return buttonName(t.button ?? -1)
    case "key": return codeDisplay(t.keyCode ?? -1) + " key"
    case "scrollUp": return "Scroll ↑"; case "scrollDown": return "Scroll ↓"
    case "scrollLeft": return "Wheel ←"; case "scrollRight": return "Wheel →"
    default: return t.kind
    }
}
func actionDesc(_ a: RuleAction?) -> String {
    guard let a = a else { return "No action set" }
    switch a.type {
    case "key": return (a.keyMods ?? []).map { $0.symbol }.joined() + codeDisplay(a.keyCode ?? -1)
    case "missionControl": return "Mission Control"; case "showDesktop": return "Show Desktop"
    case "mediaSeek": return "Seek media ◀▶"; default: return a.type
    }
}

// ───────────────────────────── Store ──────────────────────────────
final class RuleStore: ObservableObject {
    @Published var rules: [Rule] = []
    @Published var apps: [AppRef] = []
    @Published var invertVertical = false
    @Published var invertHorizontal = false
    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MouseTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }
    init() { load() }
    func load() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(SaveData.self, from: d), !s.rules.isEmpty {
            rules = s.rules; apps = s.apps
        } else { rules = RuleStore.defaults; apps = []; save() }
    }
    func save() { if let d = try? JSONEncoder().encode(SaveData(apps: apps, rules: rules)) { try? d.write(to: url) } }

    static var defaults: [Rule] {
        func k(_ c: Int, _ m: [Modifier] = []) -> RuleAction { RuleAction(type:"key", keyCode:c, keyMods:m) }
        func btn(_ n: Int, _ m: [Modifier]) -> Trigger { Trigger(kind:"button", button:n, keyCode:nil, mods:m) }
        func scr(_ kind: String, _ m: [Modifier]) -> Trigger { Trigger(kind:kind, button:nil, keyCode:nil, mods:m) }
        return [
            // Middle-click screenshot chord
            Rule(trigger: Trigger(kind:"button", button:2, keyCode:nil, mods:[.shift]), action: k(21,[.cmd,.shift])),
            // Back button (mouse button 3) — plain click left alone → native Back
            Rule(trigger: btn(3, [.cmd]),   action: k(6,[.cmd])),          // ⌘Back → Undo
            Rule(trigger: btn(3, [.shift]), action: k(48,[.cmd])),         // ⇧Back → ⌘Tab
            // Forward button (mouse button 4) — plain click left alone → native Forward
            Rule(trigger: btn(4, [.cmd]),   action: k(6,[.cmd,.shift])),   // ⌘Fwd → Redo
            Rule(trigger: btn(4, [.shift]), action: k(48,[.cmd,.shift])),  // ⇧Fwd → ⌘⇧Tab
            // Scroll gestures
            Rule(trigger: scr("scrollUp",   [.cmd]),   action: RuleAction(type:"missionControl")),
            Rule(trigger: scr("scrollDown", [.cmd]),   action: RuleAction(type:"showDesktop")),
            Rule(trigger: scr("scrollUp",   [.shift]), action: k(24,[.cmd])),
            Rule(trigger: scr("scrollDown", [.shift]), action: k(27,[.cmd])),
            Rule(trigger: scr("scrollLeft", []),  action: RuleAction(type:"mediaSeek")),
            Rule(trigger: scr("scrollRight",[]),  action: RuleAction(type:"mediaSeek")),
        ]
    }
}

// ───────────────────────────── Engine ─────────────────────────────
final class Engine {
    var store: RuleStore!
    var isRecording = false
    init() {}
    private var tap: CFMachPort?
    private let src = CGEventSource(stateID: .hidSystemState)
    private let sentinel: Int64 = 0x4D4F5530
    private let threshold = 1.0, minInterval = 0.08, flickCooldown = 0.5
    private var accum = [String: Double](), lastFire = [String: Date](), lastFlick = [String: Date]()
    private var swallowed = Set<Int64>()
    private let npLock = NSLock()
    private var npBundle: String?, npParent: String?

    func start() { startNowPlaying(); setupTap() }

    private func cgFlags(_ m: [Modifier]) -> CGEventFlags {
        var f = CGEventFlags()
        if m.contains(.cmd){f.insert(.maskCommand)}; if m.contains(.shift){f.insert(.maskShift)}
        if m.contains(.ctrl){f.insert(.maskControl)}; if m.contains(.opt){f.insert(.maskAlternate)}
        return f
    }
    private func mods(_ f: CGEventFlags) -> Set<Modifier> {
        var s = Set<Modifier>()
        if f.contains(.maskCommand){s.insert(.cmd)}; if f.contains(.maskShift){s.insert(.shift)}
        if f.contains(.maskControl){s.insert(.ctrl)}; if f.contains(.maskAlternate){s.insert(.opt)}
        return s
    }
    private func postKey(_ key: CGKeyCode, _ flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: sentinel)
            e?.post(tap: .cghidEventTap)
        }
    }
    private func runDetached(_ p: String, _ a: [String]) { let pr = Process(); pr.executableURL = URL(fileURLWithPath: p); pr.arguments = a; try? pr.run() }
    private func showDesktop() {
        // macOS has no guaranteed Show Desktop API. Default shortcut is fn+F11 on
        // most setups, so post F11 with the secondary-fn flag set. If your system's
        // Show Desktop shortcut is different/disabled, set it in System Settings →
        // Keyboard → Keyboard Shortcuts → Mission Control, or tell me the key.
        let f11: CGKeyCode = 103
        let down = CGEvent(keyboardEventSource: src, virtualKey: f11, keyDown: true)
        down?.flags = [.maskSecondaryFn]
        down?.setIntegerValueField(.eventSourceUserData, value: sentinel)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: f11, keyDown: false)
        up?.flags = [.maskSecondaryFn]
        up?.setIntegerValueField(.eventSourceUserData, value: sentinel)
        up?.post(tap: .cghidEventTap)
    }
    private func frontmost() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    private func shouldSeek(_ app: String) -> Bool {
        npLock.lock(); defer { npLock.unlock() }
        if let b = npBundle, app == b { return true }
        if let p = npParent, app == p { return true }
        return false
    }
    private func fire(_ axis: String, _ mag: Double, _ act: () -> Void) {
        accum[axis, default: 0] += mag; let now = Date()
        while abs(accum[axis]!) >= threshold {
            if now.timeIntervalSince(lastFire[axis] ?? .distantPast) >= minInterval { act(); lastFire[axis] = now }
            accum[axis]! -= (accum[axis]! > 0 ? threshold : -threshold)
        }
    }
    // App-scoped match: prefer a rule for the frontmost app, else an All-Apps rule.
    private func match(_ front: String?, _ pred: (Rule) -> Bool) -> Rule? {
        if let f = front, let r = store.rules.first(where: { $0.app == f && pred($0) }) { return r }
        return store.rules.first(where: { $0.app == nil && pred($0) })
    }
    private func runAction(_ a: RuleAction) {
        switch a.type {
        case "key": postKey(CGKeyCode(a.keyCode ?? 0), cgFlags(a.keyMods ?? []))
        case "missionControl": runDetached("/usr/bin/open", ["-a", "Mission Control"])
        case "showDesktop": showDesktop()
        default: break
        }
    }
    private func runScroll(_ rule: Rule, _ mag: Double, axis: String, front: String?) {
        guard let a = rule.action else { return }
        switch a.type {
        case "missionControl", "showDesktop":
            let now = Date()
            if now.timeIntervalSince(lastFlick[rule.id.uuidString] ?? .distantPast) >= flickCooldown {
                lastFlick[rule.id.uuidString] = now
                if a.type == "missionControl" { runDetached("/usr/bin/open", ["-a", "Mission Control"]) } else { showDesktop() }
            }
        case "key": fire(axis, mag) { self.postKey(CGKeyCode(a.keyCode ?? 0), self.cgFlags(a.keyMods ?? [])) }
        case "mediaSeek":
            guard let app = front, shouldSeek(app) else { return }
            let key: CGKeyCode = rule.trigger.kind == "scrollLeft" ? 123 : 124
            fire(axis, mag) { self.postKey(key) }
        default: break
        }
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if isRecording { return pass }
        let front = frontmost()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }; return pass
        case .keyDown:
            if event.getIntegerValueField(.eventSourceUserData) == sentinel { return pass } // our own output
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let m = mods(event.flags)
            if let r = match(front, { $0.trigger.kind == "key" && $0.trigger.keyCode == code && Set($0.trigger.mods) == m }), let a = r.action {
                runAction(a); return nil
            }
            return pass
        case .otherMouseDown:
            let b = event.getIntegerValueField(.mouseEventButtonNumber)
            if let r = match(front, { $0.trigger.kind == "button" && $0.trigger.button == Int(b) && Set($0.trigger.mods) == mods(event.flags) }), let a = r.action {
                runAction(a); swallowed.insert(b); return nil
            }
            return pass
        case .otherMouseUp:
            let b = event.getIntegerValueField(.mouseEventButtonNumber)
            if swallowed.contains(b) { swallowed.remove(b); return nil }
            return pass
        case .scrollWheel:
            let v = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let h = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            let cur = mods(event.flags)
            if cur.contains(.shift) {                       // shift folds vertical→horizontal
                let raw = v != 0 ? v : h
                let d = store.invertVertical ? -raw : raw
                if raw != 0, let r = match(front, { $0.trigger.kind == (d>0 ? "scrollUp":"scrollDown") && Set($0.trigger.mods) == cur }) { runScroll(r, raw, axis:"v", front: front); return nil }
                return pass
            }
            let vv = store.invertVertical ? -v : v, hh = store.invertHorizontal ? -h : h
            if v != 0, let r = match(front, { $0.trigger.kind == (vv>0 ? "scrollUp":"scrollDown") && Set($0.trigger.mods) == cur }) { runScroll(r, v, axis:"v", front: front); return nil }
            if h != 0, let r = match(front, { $0.trigger.kind == (hh>0 ? "scrollLeft":"scrollRight") && Set($0.trigger.mods) == cur }) { runScroll(r, h, axis:"h", front: front); return nil }
            return pass
        default: return pass
        }
    }
    private func setupTap() {
        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            Unmanaged<Engine>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { NSLog("MouseTool: tap failed — grant Accessibility & relaunch."); return }
        let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), s, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    private func startNowPlaying() {
        let cands = ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]
        guard let bin = cands.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { NSLog("media-control not found"); return }
        let proc = Process(); proc.executableURL = URL(fileURLWithPath: bin); proc.arguments = ["stream", "--no-diff"]
        let pipe = Pipe(); proc.standardOutput = pipe; var buf = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self = self else { return }
            let c = h.availableData; guard !c.isEmpty else { return }; buf.append(c)
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf.subdata(in: buf.startIndex..<nl); buf.removeSubrange(buf.startIndex...nl)
                guard let o = try? JSONSerialization.jsonObject(with: line) as? [String:Any], let p = o["payload"] as? [String:Any] else { continue }
                self.npLock.lock()
                if let b = p["bundleIdentifier"] as? String { self.npBundle = b; self.npParent = p["parentApplicationBundleIdentifier"] as? String }
                else { self.npBundle = nil; self.npParent = nil }
                self.npLock.unlock()
            }
        }
        try? proc.run()
    }
}

// ──────────────────────────── Recorder ────────────────────────────
final class Recorder: ObservableObject {
    enum Mode: Equatable { case none, trigger }
    @Published var mode: Mode = .none
    @Published var detection: String? = nil
    weak var engine: Engine?
    init() {}
    private var monitor: Any?
    func startTrigger(_ done: @escaping (Trigger) -> Void) {
        stop(); mode = .trigger; engine?.isRecording = true; detection = "Waiting…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .scrollWheel, .keyDown]) { [weak self] ev in
            guard let self = self else { return ev }
            switch ev.type {
            case .otherMouseDown:
                let n = Int(ev.buttonNumber); self.detection = "Detected: \(buttonName(n))"
                done(Trigger(kind:"button", button:n, keyCode:nil, mods:[])); self.stop(); return nil
            case .keyDown:
                let c = Int(ev.keyCode); self.detection = "Detected: \(codeDisplay(c)) key"
                done(Trigger(kind:"key", button:nil, keyCode:c, mods:[])); self.stop(); return nil
            case .scrollWheel:
                let dy = ev.scrollingDeltaY, dx = ev.scrollingDeltaX
                if dy == 0 && dx == 0 { return nil }
                let kind = abs(dy) >= abs(dx) ? (dy>0 ? "scrollUp":"scrollDown") : (dx>0 ? "scrollLeft":"scrollRight")
                self.detection = "Detected: \(kind)"
                done(Trigger(kind:kind, button:nil, keyCode:nil, mods:[])); self.stop(); return nil
            default: return ev
            }
        }
    }
    func stop() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }; mode = .none; engine?.isRecording = false }
}

// ───────────────────────────── Views ──────────────────────────────
struct ModChip: View {
    let mod: Modifier; @Binding var mods: [Modifier]; var save: () -> Void
    var on: Bool { mods.contains(mod) }
    var body: some View {
        Button(mod.symbol) { if on { mods.removeAll { $0 == mod } } else { mods.append(mod) }; save() }
            .buttonStyle(.plain).frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
            .foregroundStyle(on ? .white : .secondary)
    }
}
struct ActionEditor: View {
    @EnvironmentObject var store: RuleStore
    @Binding var rule: Rule
    var dismiss: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var parsed: RuleAction? { parseShortcut(text) }

    func suggestions() -> [String] {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
        let last = (parts.last.map(String.init) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !last.isEmpty else { return [] }
        return Array(shortcutVocab.filter { $0.lowercased().hasPrefix(last) }.prefix(5))
    }
    func complete(_ s: String) {
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map { String($0) }
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = s
        text = parts.joined(separator: "+") + "+"
    }
    func applyAndClose() { if let p = parsed { rule.action = p; store.save(); dismiss() } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type a keyboard shortcut").font(.headline)
            TextField("e.g. Command+Tab", text: $text)
                .textFieldStyle(.roundedBorder).frame(width: 240)
                .focused($focused).onSubmit { applyAndClose() }
            let sugg = suggestions()
            if !sugg.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sugg, id: \.self) { s in
                        Button(s) { complete(s) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if !text.isEmpty {
                if let p = parsed { Label(actionDesc(p), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                else { Label("Keep typing…", systemImage: "ellipsis.circle").foregroundStyle(.orange).font(.caption) }
            }
            Button("Set shortcut") { applyAndClose() }.disabled(parsed == nil).keyboardShortcut(.defaultAction)
            Divider()
            Text("Or a system action").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Mission Control") { rule.action = RuleAction(type:"missionControl"); store.save(); dismiss() }
                Button("Show Desktop") { rule.action = RuleAction(type:"showDesktop"); store.save(); dismiss() }
            }
            Button("Media Seek (wheel ◀▶)") { rule.action = RuleAction(type:"mediaSeek"); store.save(); dismiss() }
            Button("Clear action", role: .destructive) { rule.action = nil; store.save(); dismiss() }
        }
        .padding(18).frame(width: 290)
        .onAppear {
            if let a = rule.action, a.type == "key" {
                let m = (a.keyMods ?? []).map { $0.fullName }.joined(separator: "+"); let k = codeDisplay(a.keyCode ?? -1)
                text = m.isEmpty ? k : "\(m)+\(k)"
            }
            focused = true
        }
    }
}
struct RuleRow: View {
    @EnvironmentObject var store: RuleStore
    @Binding var rule: Rule
    @State private var editing = false
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) { ForEach(Modifier.allCases, id: \.self) { m in ModChip(mod: m, mods: $rule.trigger.mods) { store.save() } } }
            Text(triggerBase(rule.trigger)).frame(width: 130, alignment: .leading).font(.system(.body, design: .rounded))
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            Button { editing = true } label: {
                Text(actionDesc(rule.action)).foregroundStyle(rule.action == nil ? .secondary : .primary).frame(width: 150, alignment: .leading)
            }.buttonStyle(.bordered).popover(isPresented: $editing) { ActionEditor(rule: $rule, dismiss: { editing = false }).environmentObject(store) }
            Spacer()
            Button(role: .destructive) { store.rules.removeAll { $0.id == rule.id }; store.save() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }.padding(.vertical, 4).padding(.horizontal, 8)
    }
}
struct TabChip: View {
    let title: String; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).fontWeight(selected ? .semibold : .regular) }
            .buttonStyle(.plain).padding(.vertical, 5).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.secondary.opacity(0.12)))
            .foregroundStyle(selected ? .white : .primary)
    }
}
struct ContentView: View {
    @EnvironmentObject var store: RuleStore
    @EnvironmentObject var rec: Recorder
    @State private var scope: String? = nil       // nil = All Apps
    var recording: Bool { rec.mode == .trigger }

    func addApp() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK, let u = p.url, let b = Bundle(url: u)?.bundleIdentifier {
            let name = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
            if !store.apps.contains(where: { $0.bundleID == b }) { store.apps.append(AppRef(bundleID: b, name: name)); store.save() }
            scope = b
        }
    }
    // Stable binding into store.rules by id — keeps scroll position steady.
    func bindingFor(_ rule: Rule) -> Binding<Rule> {
        guard let i = store.rules.firstIndex(where: { $0.id == rule.id }) else { return .constant(rule) }
        return $store.rules[i]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage())
                    .resizable().frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MouseTool").font(.title2).bold()
                    Text("Per-app mouse & key rules").font(.caption).foregroundStyle(.secondary)
                }
            }
            // App tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TabChip(title: "All Apps", selected: scope == nil) { scope = nil }
                    ForEach(store.apps) { a in TabChip(title: a.name, selected: scope == a.bundleID) { scope = a.bundleID } }
                    Button { addApp() } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
                    if let s = scope {
                        Button(role: .destructive) {
                            store.rules.removeAll { $0.app == s }; store.apps.removeAll { $0.bundleID == s }; store.save(); scope = nil
                        } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                    }
                }
            }
            // Capture box
            GroupBox {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(recording ? Color.green : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: recording ? 2.5 : 1, dash: recording ? [] : [5]))
                        VStack(spacing: 6) {
                            Image(systemName: recording ? "record.circle.fill" : "plus.circle").font(.system(size: 26)).foregroundStyle(recording ? .green : .secondary)
                            Text(recording ? "Now click a button or scroll — no modifiers yet"
                                            : "Click here, then click a mouse button, scroll the wheel, or press a key")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(height: 92).contentShape(Rectangle())
                    .onTapGesture {
                        if recording { rec.stop() }
                        else { rec.startTrigger { t in store.rules.append(Rule(trigger: t, action: nil, app: scope)); store.save() } }
                    }
                    if let d = rec.detection { Text(d).font(.caption).foregroundStyle(d.hasPrefix("Detected") ? .green : .orange).frame(maxWidth: .infinity, alignment: .leading) }
                    Text("Adding to: \(scope == nil ? "All Apps" : (store.apps.first { $0.bundleID == scope }?.name ?? scope!)) · set modifiers with the chips below.")
                        .font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(4)
            } label: { Label("Add a rule", systemImage: "plus") }
            // Rules for current scope
            GroupBox {
                ScrollView {
                    VStack(spacing: 2) {
                        let visible = store.rules.filter { $0.app == scope }
                        if visible.isEmpty { Text("No rules in this tab yet").foregroundStyle(.secondary).padding() }
                        ForEach(visible) { rule in
                            RuleRow(rule: bindingFor(rule))
                            Divider().opacity(0.4)
                        }
                    }.padding(.vertical, 2)
                }
            } label: { Label(scope == nil ? "Rules — All Apps" : "Rules — \(store.apps.first { $0.bundleID == scope }?.name ?? "")", systemImage: "list.bullet") }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GroupBox {
                HStack(spacing: 24) {
                    Toggle("Invert vertical", isOn: $store.invertVertical)
                    Toggle("Invert horizontal", isOn: $store.invertHorizontal)
                    Spacer()
                    Button("Reset to defaults", role: .destructive) {
                        store.rules = RuleStore.defaults; store.apps = []; store.save(); scope = nil
                    }.controlSize(.small)
                }.padding(4)
            } label: { Label("Scrolling", systemImage: "scroll") }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, maxWidth: .infinity, minHeight: 520, idealHeight: 780, maxHeight: .infinity)
    }
}

@main
struct MouseToolApp: App {
    @StateObject private var store = RuleStore()
    @StateObject private var rec = Recorder()
    private let engine = Engine()
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    func setup() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        engine.store = store; rec.engine = engine; engine.start()
    }

    var body: some Scene {
        WindowGroup("MouseTool", id: "MouseTool") {
            ContentView().environmentObject(store).environmentObject(rec).onAppear { setup() }
        }

        MenuBarExtra {
            MenuContent(store: store, launchAtLogin: $launchAtLogin)
        } label: {
            if let img = NSImage(named: "MenuBarIcon") {
                Image(nsImage: img)
            } else {
                Image(systemName: "cursorarrow.click.2")
            }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var store: RuleStore
    @Binding var launchAtLogin: Bool
    @Environment(\.openWindow) private var openWindow

    func front() -> (id: String?, name: String) {
        let a = NSWorkspace.shared.frontmostApplication
        return (a?.bundleIdentifier, a?.localizedName ?? "Current app")
    }
    func lines(for app: String?) -> [String] {
        store.rules.filter { $0.app == app && $0.action != nil }.map { r in
            let mods = r.trigger.mods.map { $0.symbol }.joined()
            return "\(mods)\(triggerBase(r.trigger))  →  \(actionDesc(r.action))"
        }
    }

    var body: some View {
        let f = front()
        let appLines = f.id != nil ? lines(for: f.id) : []
        let globalLines = lines(for: nil)

        if !appLines.isEmpty {
            Text(f.name).font(.headline)
            ForEach(appLines, id: \.self) { Text($0) }
            Divider()
        }
        Text("All Apps").font(.headline)
        if globalLines.isEmpty { Text("No global rules").foregroundStyle(.secondary) }
        ForEach(globalLines, id: \.self) { Text($0) }
        Divider()
        Button("Open MouseTool…") { openWindow(id: "MouseTool"); NSApp.activate(ignoringOtherApps: true) }
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { NSLog("login item error: \(error)") }
            }
        Divider()
        Button("Quit MouseTool") { NSApp.terminate(nil) }
    }
}
