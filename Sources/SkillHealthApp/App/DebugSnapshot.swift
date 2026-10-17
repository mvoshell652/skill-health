import AppKit

#if DEBUG

/// Debug builds only. Launched with `-snapshotWindows YES`, Skill Health writes a PNG of each titled
/// window into its temporary folder shortly after launch, so a change to a window can be checked
/// without granting screen recording to whatever is checking it.
enum DebugSnapshot {
    /// `-debugShowMainWindow YES` opens the window at launch. Use it, never an override of
    /// `showInMenuBar`: MenuBarExtra writes a hidden item back to that key, so a one-run
    /// override would switch the person's menu bar icon off for good.
    static var showsWindow: Bool { UserDefaults.standard.bool(forKey: "debugShowMainWindow") }
    /// `-debugShowFinding YES` opens the evidence window of the sample finding's skill. The sample is
    /// inert (Finding.isSample): the window offers no hand-off to Claude Code, and it is never
    /// published. On 2026-10-03 a live "Write It" on the sample patched the owner's real supabase
    /// skill, which is why a sample must not be able to act on anything.
    static var showsFinding: Bool { UserDefaults.standard.bool(forKey: "debugShowFinding") }
    /// `-debugShowLoginOffer YES` shows the setup window's Launch at login offer whatever the state, to check
    /// its layout. The offer is inert then (see `LoginOfferRow`).
    static var showsLoginOffer: Bool { UserDefaults.standard.bool(forKey: "debugShowLoginOffer") }
    /// `-debugSampleFindings N` shows N sample findings in the menu. The menu then behaves as it does
    /// for the sample library: review rows only, nothing handed to Claude Code.
    static var injectsSamples: Bool { UserDefaults.standard.integer(forKey: "debugSampleFindings") > 0 }
    static func scheduleIfAsked() {
        guard UserDefaults.standard.bool(forKey: "snapshotWindows") else { return }
        Task {
            // Long enough for the window to settle at its final size (-snapshotDelay to wait longer).
            let delay = max(6, UserDefaults.standard.double(forKey: "snapshotDelay"))
            try? await Task.sleep(for: .seconds(delay))
            // Titled windows and the sheets attached to them; never the menu bar's own windows.
            for window in NSApplication.shared.windows where window.isVisible && window.contentView != nil
                && !String(describing: type(of: window)).contains("StatusBar") {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let name = window.isSheet ? "sheet" : window.title
                let file = URL.temporaryDirectory.appending(path: "snapshot-\(name).png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
    }
}

extension DebugSnapshot {
    private static var dumped = false

    /// Debug builds only. `-dumpMenu YES` opens the menu bar extra's menu once, writes every item
    /// as AppKit built it (title, subtitle, header, dimmed, submenus) to menu.txt in the temporary
    /// folder, and closes it: a menu can't be snapshotted, but its structure can be checked.
    static func dumpMenuIfAsked() {
        guard UserDefaults.standard.bool(forKey: "dumpMenu") else { return }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            // AppKit posts menu tracking on the main thread; the menu never leaves it.
            nonisolated(unsafe) let menu = note.object as? NSMenu
            MainActor.assumeIsolated {
                guard !dumped, let menu, menu.supermenu == nil else { return }
                dumped = true
                write(describe(menu, depth: 0))
                menu.cancelTracking()
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(8))
            // On macOS 27 the status item's window holds a content view, not a button; the item
            // itself is reachable from it (private, so debug builds only, and checked first).
            var items: [NSStatusItem] = []
            for window in NSApplication.shared.windows {
                for object in [window as NSObject, window.contentView as NSObject?].compactMap({ $0 }) {
                    for key in ["statusItem", "_statusItem"] where object.responds(to: Selector((key))) {
                        if let item = object.value(forKey: key) as? NSStatusItem { items.append(item) }
                    }
                }
            }
            if items.isEmpty, let all = NSStatusBar.system.value(forKey: "_statusItems") as? [NSStatusItem] {
                items = all
            }
            if items.isEmpty {
                var names: [String] = []
                for cls in [NSStatusBar.self as AnyClass, NSClassFromString("NSStatusBarWindow"), NSClassFromString("NSStatusBarContentView")].compactMap({ $0 }) {
                    var count: UInt32 = 0
                    if let ivars = class_copyIvarList(cls, &count) {
                        names += (0..<Int(count)).compactMap { ivar_getName(ivars[$0]).map { "\(cls).\(String(cString: $0))" } }
                        free(ivars)
                    }
                }
                write("no status item; ivars:\n" + names.joined(separator: "\n"))
                return
            }
            guard let item = items.first(where: { $0.menu != nil }) ?? items.first else {
                write("no status item reachable from \(NSApplication.shared.windows.count) windows")
                return
            }
            if let menu = item.menu {
                // Ask SwiftUI to fill the menu as it would before showing it, then read it.
                menu.delegate?.menuWillOpen?(menu)
                write(describe(menu, depth: 0))
                menu.delegate?.menuDidClose?(menu)
                dumped = true
                // Then open it for real and photograph what AppKit draws, separators and all.
                // The timer fires on the main run loop during menu tracking; the menu stays there.
                nonisolated(unsafe) let opened = menu
                let shoot = Timer(timeInterval: 0.8, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        for window in NSApplication.shared.windows where window.isVisible
                            && String(describing: type(of: window)).localizedCaseInsensitiveContains("menu") {
                            // The system composites menus, so pixels come back blank; the laid-out
                            // view tree still says which rows and separators are really there.
                            guard let root = window.contentView?.superview ?? window.contentView else { continue }
                            let tree = "window \(type(of: window)) \(window.frame.size)\n" + viewTree(root, in: root, depth: 0)
                            try? tree.write(to: URL.temporaryDirectory.appending(path: "menu-views.txt"), atomically: true, encoding: .utf8)
                        }
                        opened.cancelTracking()
                    }
                }
                RunLoop.main.add(shoot, forMode: .common)
                // The menu bar item itself is drawn by the system on macOS 27 and ignores a click
                // from here, so pop the same menu up over Skill Health's own window instead.
                if let view = NSApplication.shared.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })?.contentView {
                    opened.popUp(positioning: nil, at: NSPoint(x: 40, y: view.bounds.height - 40), in: view)
                } else {
                    write("open a window first: launch with -debugShowMainWindow YES as well")
                }
            } else if let button = item.button {
                button.performClick(nil)
                try? await Task.sleep(for: .seconds(2))
                if !dumped { write("the status item has no menu and its button opened none") }
            } else {
                write("the status item has neither a menu nor a button")
            }
        }
    }

    private static func viewTree(_ view: NSView, in root: NSView, depth: Int) -> String {
        let text = (view as? NSTextField)?.stringValue ?? ""
        var line = String(repeating: "  ", count: depth)
            + "\(type(of: view)) y=\(Int(view.convert(view.bounds, to: root).minY)) h=\(Int(view.frame.height))"
        if view.isHidden { line += " HIDDEN" }
        if !text.isEmpty { line += " \"\(text)\"" }
        return line + "\n" + view.subviews.map { viewTree($0, in: root, depth: depth + 1) }.joined()
    }

    private static func describe(_ menu: NSMenu, depth: Int) -> String {
        menu.delegate?.menuNeedsUpdate?(menu)
        var lines = ""
        for item in menu.items {
            let indent = String(repeating: "    ", count: depth)
            if item.isSeparatorItem { lines += indent + "────" + (item.isHidden ? "   (hidden)" : "") + "\n"; continue }
            var line = indent + (item.isSectionHeader ? "[header] " : "") + item.title
            if let subtitle = item.subtitle, !subtitle.isEmpty { line += "   ‹subtitle: \(subtitle)›" }
            if let label = item.accessibilityLabel(), !label.isEmpty, label != item.title { line += "   ‹voiceover: \(label)›" }
            if !item.isEnabled { line += "   (dimmed)" }
            if item.isHidden { line += "   (hidden)" }
            if item.state == .on { line += "   ✓" }
            if !item.keyEquivalent.isEmpty { line += "   ⌘\(item.keyEquivalent)" }
            lines += line + "\n"
            if let submenu = item.submenu { lines += describe(submenu, depth: depth + 1) }
        }
        return lines
    }

    private static func write(_ text: String) {
        try? text.write(to: URL.temporaryDirectory.appending(path: "menu.txt"), atomically: true, encoding: .utf8)
    }
}
#else
enum DebugSnapshot {
    static let showsWindow = false
    static let showsFinding = false
    static let injectsSamples = false
}
#endif
