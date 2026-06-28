// mousehid.swift — ProtoArc EM11 Pro (v5: write-then-getReport proof test)
//
// Goal: prove definitively whether the device RECEIVES our writes, by reading
// a report straight back with IOHIDDeviceGetReport after writing. If GetReport
// returns real bytes (and they reflect our write), native IOKit is alive. If it
// errors or returns zeros on every interface, native is dead and we go WebHID.
//
// Build: swiftc mousehid.swift -o mousehid -framework IOKit -framework CoreFoundation
// Run:   ./mousehid --probe-rw      (writes a marker, then GetReports every which way)
//        ./mousehid --list

import Foundation
import IOKit
import IOKit.hid

func frame(_ b0: [UInt8]) -> [UInt8] {
    var b = b0; while b.count < 15 { b.append(0) }; b = Array(b.prefix(15))
    var s = 0; for x in b { s += Int(x) }; b.append(UInt8((0x4d - s) & 0xff)); return b
}
func handshake() -> [UInt8] { frame([0x01,0x00,0x00,0x00,0x08,0x93,0x48,0x71,0xcf]) }
func readFrame(addr: UInt8) -> [UInt8] { frame([0x08,0x00,0x00,addr,0x0a]) }
func macroFrame(slot: UInt8, usage: UInt8) -> [UInt8] { frame([0x07,0x00,0x01,slot,0x08,0x02,0x81,usage,0x00,0x41,usage,0x00,0x07,0x00,0x00]) }
func modeMacro(addr: UInt8) -> [UInt8] { frame([0x07,0x00,0x00,addr,0x04,0x05,0x00,0x00,UInt8((0x55-0x05)&0xff)]) }
func hexs(_ b: ArraySlice<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func hexs(_ b: [UInt8]) -> String { hexs(b[...]) }

final class HIDTool {
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    func all() -> [IOHIDDevice] {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, nil); IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        return Array((IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? [])
    }
    func ip(_ d: IOHIDDevice, _ k: String) -> Int? { (IOHIDDeviceGetProperty(d, k as CFString) as? NSNumber)?.intValue }
    func sp(_ d: IOHIDDevice, _ k: String) -> String? { IOHIDDeviceGetProperty(d, k as CFString) as? String }
    func tag(_ d: IOHIDDevice) -> String {
        String(format: "VID 0x%04x PID 0x%04x page 0x%04x usage 0x%02x  %@",
            ip(d,kIOHIDVendorIDKey) ?? 0, ip(d,kIOHIDProductIDKey) ?? 0,
            ip(d,kIOHIDPrimaryUsagePageKey) ?? 0, ip(d,kIOHIDPrimaryUsageKey) ?? 0, sp(d,kIOHIDProductKey) ?? "?")
    }
    func list() { for d in all() { print(tag(d)) } }

    // Try a GetReport of each type/id; print what comes back.
    func getReport(_ d: IOHIDDevice, type: IOHIDReportType, id: Int) -> String {
        var len: CFIndex = 64
        for i in 0..<64 { buf[i] = 0 }
        let r = IOHIDDeviceGetReport(d, type, CFIndex(id), buf, &len)
        if r != kIOReturnSuccess { return String(format: "ERR 0x%08x", r) }
        let bytes = (0..<min(Int(len), 16)).map { buf[$0] }
        let nonzero = bytes.contains { $0 != 0 }
        return "\(hexs(bytes))\(nonzero ? "  <-- DATA" : "  (all zero)")"
    }

    func probeRW() {
        for d in all() {
            let page = ip(d, kIOHIDPrimaryUsagePageKey) ?? 0
            let isPA = (sp(d, kIOHIDProductKey) ?? "").contains("ProtoArc")
            guard page >= 0xff00 || isPA else { continue }
            print("\n=== \(tag(d)) ===")
            guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { print("  can't open"); continue }
            // 1) baseline read of button region BEFORE
            print("  GetReport BEFORE write:")
            for (tn, tt) in [("out", kIOHIDReportTypeOutput), ("feat", kIOHIDReportTypeFeature), ("in", kIOHIDReportTypeInput)] {
                for id in [8, 0] { print("    \(tn) id=\(id): \(getReport(d, type: tt, id: id))") }
            }
            // 2) write a distinctive marker: set Forward(0x70) to F13 via output and feature
            for tt in [kIOHIDReportTypeOutput, kIOHIDReportTypeFeature] {
                _ = IOHIDDeviceSetReport(d, tt, 8, handshake(), 16)
                _ = IOHIDDeviceSetReport(d, tt, 8, macroFrame(slot: 0x80, usage: 0x68), 16)
                _ = IOHIDDeviceSetReport(d, tt, 8, modeMacro(addr: 0x70), 16)
                _ = IOHIDDeviceSetReport(d, tt, 8, readFrame(addr: 0x70), 16)
                CFRunLoopRunInMode(.defaultMode, 0.1, false)
            }
            // 3) GetReport AFTER write — did anything change / return data?
            print("  GetReport AFTER write:")
            for (tn, tt) in [("out", kIOHIDReportTypeOutput), ("feat", kIOHIDReportTypeFeature), ("in", kIOHIDReportTypeInput)] {
                for id in [8, 0] { print("    \(tn) id=\(id): \(getReport(d, type: tt, id: id))") }
            }
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        print("\nVerdict guide:")
        print("  • Any 'DATA' line that differs BEFORE vs AFTER = the device received our write. Native is ALIVE.")
        print("  • All 'ERR' / 'all zero' everywhere = device never accepts GetReport from a CLI. Native likely dead → WebHID.")
    }
}

let tool = HIDTool()
if CommandLine.arguments.contains("--list") { tool.list(); exit(0) }
if CommandLine.arguments.contains("--probe-rw") { tool.probeRW(); exit(0) }
print("Run: ./mousehid --probe-rw")
