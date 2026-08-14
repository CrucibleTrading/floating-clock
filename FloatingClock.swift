// FloatingClock — an always-on-top HH:MM:SS clock for macOS.
//
// Unlike a desktop widget (which renders behind all windows), this is a
// borderless floating panel that stays above normal windows, follows you across
// Spaces, and survives fullscreen apps. Toggle it from the menu bar.
//
// Build:  swiftc -O FloatingClock.swift -o FloatingClock

import Cocoa

// MARK: - Clock view

final class ClockView: NSView {
    var text = "00:00:00"
    var fontSize: CGFloat = 72
    var showBackdrop = true

    private var font: NSFont {
        // Monospaced digits so the width never jitters as the seconds tick.
        NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    }

    func fittingSize(for sample: String = "00:00:00") -> NSSize {
        let s = (sample as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(s.width) + 36, height: ceil(s.height) + 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        if showBackdrop {
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        }
        let str = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
        ])
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                             y: (bounds.height - sz.height) / 2))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var view: ClockView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastRendered = ""

    private let d = UserDefaults.standard
    private var visible = true
    private var use24Hour = false
    private var alwaysOnTopOfEverything = false

    private let sizeChoices: [(String, CGFloat)] =
        [("Small", 32), ("Medium", 48), ("Large", 72), ("Huge", 108)]

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon

        // restore prefs
        let savedSize = d.object(forKey: "fontSize") as? Double ?? 72
        use24Hour = d.bool(forKey: "use24Hour")
        alwaysOnTopOfEverything = d.bool(forKey: "aggressiveLevel")
        visible = d.object(forKey: "visible") as? Bool ?? true

        view = ClockView()
        view.fontSize = CGFloat(savedSize)

        let size = view.fittingSize()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true      // drag it anywhere
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        applyLevel()

        // restore position, else top-right of the main screen
        if let f = d.string(forKey: "origin") {
            window.setFrameOrigin(NSPointFromString(f))
        } else if let scr = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: scr.visibleFrame.maxX - size.width - 24,
                                          y: scr.visibleFrame.maxY - size.height - 24))
        }
        if visible { window.orderFrontRegardless() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(saveOrigin),
            name: NSWindow.didMoveNotification, object: window)

        buildMenu()
        tick()
        timer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                                     selector: #selector(tick),
                                     userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)     // keep ticking during drags
    }

    private func applyLevel() {
        // .floating sits above normal windows. .screenSaver also covers most
        // system UI — useful on a second monitor, obnoxious on a laptop.
        window.level = alwaysOnTopOfEverything ? .screenSaver : .floating
    }

    // MARK: menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⏱"

        let menu = NSMenu()
        menu.addItem(withTitle: visible ? "Hide Clock" : "Show Clock",
                     action: #selector(toggleVisible), keyEquivalent: "h").target = self
        menu.addItem(.separator())

        let sizeMenu = NSMenu()
        for (label, pts) in sizeChoices {
            let mi = NSMenuItem(title: label, action: #selector(setSize(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = pts
            mi.state = (abs(view.fontSize - pts) < 0.5) ? .on : .off
            sizeMenu.addItem(mi)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        menu.addItem(sizeItem)
        menu.setSubmenu(sizeMenu, for: sizeItem)

        let fmt = NSMenuItem(title: "24-Hour Time", action: #selector(toggle24), keyEquivalent: "")
        fmt.target = self; fmt.state = use24Hour ? .on : .off
        menu.addItem(fmt)

        let bg = NSMenuItem(title: "Background Panel", action: #selector(toggleBackdrop), keyEquivalent: "")
        bg.target = self; bg.state = view.showBackdrop ? .on : .off
        menu.addItem(bg)

        let lvl = NSMenuItem(title: "Float Above Everything", action: #selector(toggleLevel), keyEquivalent: "")
        lvl.target = self; lvl.state = alwaysOnTopOfEverything ? .on : .off
        menu.addItem(lvl)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: actions

    @objc private func toggleVisible() {
        visible.toggle()
        visible ? window.orderFrontRegardless() : window.orderOut(nil)
        d.set(visible, forKey: "visible")
        buildMenu()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let pts = sender.representedObject as? CGFloat else { return }
        view.fontSize = pts
        d.set(Double(pts), forKey: "fontSize")
        resizeToFit()
        buildMenu()
    }

    @objc private func toggle24() {
        use24Hour.toggle(); d.set(use24Hour, forKey: "use24Hour")
        lastRendered = ""; tick(); resizeToFit(); buildMenu()
    }

    @objc private func toggleBackdrop() {
        view.showBackdrop.toggle(); view.needsDisplay = true; buildMenu()
    }

    @objc private func toggleLevel() {
        alwaysOnTopOfEverything.toggle()
        d.set(alwaysOnTopOfEverything, forKey: "aggressiveLevel")
        applyLevel(); buildMenu()
    }

    @objc private func saveOrigin() {
        d.set(NSStringFromPoint(window.frame.origin), forKey: "origin")
    }

    private func resizeToFit() {
        let origin = window.frame.origin
        let sample = use24Hour ? "00:00:00" : "00:00:00 AM"
        var f = window.frame
        f.size = view.fittingSize(for: sample)
        f.origin = origin
        window.setFrame(f, display: true)
        view.needsDisplay = true
    }

    @objc private func tick() {
        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .second], from: now)
        var h = c.hour ?? 0
        var suffix = ""
        if !use24Hour {
            suffix = h < 12 ? " AM" : " PM"
            h = h % 12
            if h == 0 { h = 12 }
        }
        let s = String(format: "%02d:%02d:%02d", h, c.minute ?? 0, c.second ?? 0) + suffix
        guard s != lastRendered else { return }
        lastRendered = s
        view.text = s
        view.needsDisplay = true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
