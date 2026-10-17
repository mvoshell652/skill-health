// A development aid for checking Skill Health's windows and menu the way assistive technology meets them,
// on a THROWAWAY copy of the app only (bundle id com.mvoshell.skillhealth.firstrun, so it starts with an
// empty container and can never touch the person's real Skill Health). It reads the accessibility tree and
// presses controls by their label, through the accessibility API.
//
//   swiftc -O Scripts/dev/ax.swift -o /tmp/ax
//   /tmp/ax <pid> dump              every window's controls and text, in reading order
//   /tmp/ax <pid> press <label> [n] press the nth control whose label is or starts with <label>
//   /tmp/ax <pid> menu [item]       open the menu bar extra, list it, and optionally choose an item
//
// The calling terminal needs Accessibility permission (System Settings › Privacy & Security).
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else { print("usage: ax <pid> dump | press <label> [n] | menu [item]"); exit(2) }
guard let running = NSRunningApplication(processIdentifier: pid),
      running.bundleIdentifier == "com.mvoshell.skillhealth.firstrun" else { print("refusing: not the throwaway first-run copy"); exit(2) }
let app = AXUIElementCreateApplication(pid)

func attr(_ e: AXUIElement, _ k: String) -> Any? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
func label(_ e: AXUIElement) -> String {
    for k in ["AXDescription", "AXTitle"] { if let s = attr(e, k) as? String, !s.isEmpty { return s } }
    return ""
}
let shown: Set<String> = ["AXButton", "AXCheckBox", "AXStaticText", "AXTextField", "AXTextArea", "AXRadioButton", "AXPopUpButton",
                          "AXLink", "AXHeading", "AXProgressIndicator", "AXImage", "AXMenuButton", "AXDisclosureTriangle"]
// Some trees refer back to an ancestor; a visited set and a depth limit keep a walk finite.
var visited = Set<Int>()
func seen(_ e: AXUIElement) -> Bool { !visited.insert(Int(CFHash(e))).inserted }

func walk(_ e: AXUIElement, _ depth: Int) {
    guard depth < 60, !seen(e) else { return }
    let role = attr(e, "AXRole") as? String ?? "?"
    let sub = attr(e, "AXSubrole") as? String ?? ""
    if shown.contains(role), !["AXCloseButton", "AXZoomButton", "AXMinimizeButton", "AXFullScreenButton"].contains(sub) {
        var parts: [String] = []
        let l = label(e)
        if !l.isEmpty { parts.append("\"\(l)\"") }
        if let v = attr(e, "AXValue"), CFGetTypeID(v as CFTypeRef) != AXValueGetTypeID() {
            let s = "\(v)"
            if !s.isEmpty { parts.append("value=\(s.prefix(400))") }
        }
        if let h = attr(e, "AXHelp") as? String, !h.isEmpty { parts.append("help=\(h)") }
        if !sub.isEmpty { parts.append(sub) }
        if let t = attr(e, "AXTitleUIElement"), CFGetTypeID(t as CFTypeRef) == AXUIElementGetTypeID() {
            parts.append("labelledBy=\(attr(t as! AXUIElement, "AXValue").map { "\($0)" } ?? "?")")
        }
        if (attr(e, "AXEnabled") as? Bool) == false { parts.append("DISABLED") }
        print(String(repeating: " ", count: depth) + role.dropFirst(2) + " " + parts.joined(separator: " | "))
    }
    for child in children(e) { walk(child, depth + 1) }
}
func find(_ e: AXUIElement, _ wanted: String, _ found: inout [AXUIElement], _ depth: Int = 0) {
    guard depth < 60 else { return }
    let role = attr(e, "AXRole") as? String ?? ""
    if ["AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXPopUpButton", "AXLink"].contains(role) {
        let l = label(e)
        if l == wanted || l.hasPrefix(wanted) { found.append(e) }
    }
    for child in children(e) { find(child, wanted, &found, depth + 1) }
}
let windows = (attr(app, "AXWindows") as? [AXUIElement]) ?? []
switch args[2] {
case "dump":
    print("windows: \(windows.count)")
    for w in windows {
        var pos = CGPoint.zero, size = CGSize.zero
        if let p = attr(w, "AXPosition"), CFGetTypeID(p as CFTypeRef) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = attr(w, "AXSize"), CFGetTypeID(s as CFTypeRef) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        print("WINDOW \"\(attr(w, "AXTitle") ?? "?")\" top \(Int(pos.y)) height \(Int(size.height)) bottom \(Int(pos.y + size.height)) (screen \(Int(NSScreen.main?.frame.height ?? 0)))")
        walk(w, 0)
    }
case "press":
    var found: [AXUIElement] = []
    for w in windows { find(w, args[3], &found) }
    let n = args.count > 4 ? Int(args[4])! : 0
    guard found.count > n else { print("not found: \(args[3]) (\(found.count) matches)"); exit(1) }
    print("press \(args[3]):", AXUIElementPerformAction(found[n], kAXPressAction as CFString) == .success ? "ok" : "failed")
case "menu":
    guard let bar = attr(app, "AXExtrasMenuBar"), let item = children(bar as! AXUIElement).first else { print("no menu bar extra"); exit(1) }
    print("extra: \"\(label(item))\"")
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 1.2)
    func menu(_ e: AXUIElement, _ depth: Int) {
        for c in children(e) {
            let role = attr(c, "AXRole") as? String ?? ""
            if role == "AXMenuItem" {
                let title = attr(c, "AXTitle") as? String ?? ""
                let enabled = (attr(c, "AXEnabled") as? Bool) ?? true
                let cmd = attr(c, "AXMenuItemCmdChar") as? String ?? ""
                print(String(repeating: "    ", count: depth) + (title.isEmpty ? "────" : title) + (enabled ? "" : "  (dimmed)") + (cmd.isEmpty ? "" : "  ⌘\(cmd)"))
            }
            menu(c, role == "AXMenuItem" ? depth + 1 : depth)
        }
    }
    menu(item, 0)
    if args.count > 3 {
        var found: [AXUIElement] = []
        find(item, args[3], &found)
        if let target = found.first { print("choose \(args[3]):", AXUIElementPerformAction(target, kAXPressAction as CFString) == .success ? "ok" : "failed") }
        else { print("menu item not found: \(args[3])"); AXUIElementPerformAction(item, kAXCancelAction as CFString) }
    } else {
        AXUIElementPerformAction(item, kAXCancelAction as CFString)
    }
default: print("unknown")
}
