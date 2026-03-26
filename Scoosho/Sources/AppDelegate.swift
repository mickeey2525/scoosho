import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let settingsManager = SettingsManager()
    let captureManager = CaptureManager()
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        registerHotKeys()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Scoosho")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Element", action: #selector(captureElement), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Deep Element (Web)", action: #selector(captureDeepElement), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let formatItem = NSMenuItem(title: "Format: \(settingsManager.imageFormat.rawValue.uppercased())", action: nil, keyEquivalent: "")
        formatItem.tag = 100
        menu.addItem(formatItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Scoosho", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func refreshMenu() {
        if let menu = statusItem?.menu,
           let formatItem = menu.item(withTag: 100) {
            formatItem.title = "Format: \(settingsManager.imageFormat.rawValue.uppercased())"
        }
    }

    @objc private func captureElement() {
        captureManager.captureElement(settingsManager: settingsManager)
    }

    @objc private func captureDeepElement() {
        captureManager.captureDeepElement(settingsManager: settingsManager)
    }

    @objc private func captureWindow() {
        captureManager.captureWindow(settingsManager: settingsManager)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(settingsManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scoosho Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Global Hot Keys

    private func registerHotKeys() {
        installEventHandler()
        registerHotKey(id: 1, keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey))
        registerHotKey(id: 2, keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(cmdKey | shiftKey))
        registerHotKey(id: 3, keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey))
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerRef = UnsafeMutablePointer<AppDelegate>.allocate(capacity: 1)
        handlerRef.initialize(to: self)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                switch hotKeyID.id {
                case 1:
                    appDelegate.captureElement()
                case 2:
                    appDelegate.captureWindow()
                case 3:
                    appDelegate.captureDeepElement()
                default:
                    break
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343_484F), id: id) // "SCHO"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRefs.append(hotKeyRef)
    }
}
