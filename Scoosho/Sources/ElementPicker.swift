import AppKit
import ApplicationServices

final class ElementPicker {
    private var overlayWindow: NSWindow?
    private var eventMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var currentFrame: CGRect = .zero
    private var completion: ((CGRect?) -> Void)?

    func start(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        guard trusted else {
            print("Accessibility permission not granted")
            completion(nil)
            return
        }

        setupOverlayWindow()
        startMonitoring()
    }

    // MARK: - Overlay Window

    private func setupOverlayWindow() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let highlightView = HighlightView(frame: .zero)
        window.contentView = highlightView

        self.overlayWindow = window
    }

    private func updateOverlay(frame: CGRect) {
        guard frame != currentFrame, frame.width > 0, frame.height > 0 else { return }
        currentFrame = frame

        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let screenFrame = screen.frame

        let cocoaY = screenFrame.maxY - frame.origin.y - frame.height
        let windowFrame = CGRect(x: frame.origin.x, y: cocoaY, width: frame.width, height: frame.height)

        overlayWindow?.setFrame(windowFrame, display: false)
        overlayWindow?.contentView?.setNeedsDisplay(overlayWindow!.contentView!.bounds)
        overlayWindow?.orderFront(nil)
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
    }

    // MARK: - Event Monitoring

    private func startMonitoring() {
        NSCursor.crosshair.push()

        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove(event: event)
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self = self else { return }
            if event.type == .keyDown && event.keyCode == 53 {
                self.cancel()
                return
            }
            if event.type == .leftMouseDown {
                self.selectCurrentElement()
                return
            }
        }

        let localMouseMove = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event: event)
            return event
        }
        objc_setAssociatedObject(self, "localMouseMove", localMouseMove, .OBJC_ASSOCIATION_RETAIN)

        let localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                self.cancel()
                return nil
            }
            if event.type == .leftMouseDown {
                self.selectCurrentElement()
                return nil
            }
            return event
        }
        objc_setAssociatedObject(self, "localClick", localClick, .OBJC_ASSOCIATION_RETAIN)
    }

    private func handleMouseMove(event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let axX = mouseLocation.x
        let axY = screen.frame.maxY - mouseLocation.y

        if let frame = elementFrame(at: CGPoint(x: axX, y: axY)) {
            updateOverlay(frame: frame)
        }
    }

    private func selectCurrentElement() {
        let result = currentFrame.width > 0 && currentFrame.height > 0 ? currentFrame : nil
        cleanup()
        completion?(result)
        completion = nil
    }

    private func cancel() {
        cleanup()
        completion?(nil)
        completion = nil
    }

    private func cleanup() {
        NSCursor.pop()
        hideOverlay()

        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for key in ["localMouseMove", "localClick"] {
            if let monitor = objc_getAssociatedObject(self, key) {
                NSEvent.removeMonitor(monitor)
                objc_setAssociatedObject(self, key, nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }

        overlayWindow = nil
    }

    // MARK: - Accessibility Element Detection

    private func elementFrame(at point: CGPoint) -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element = element else { return nil }

        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        if size.width < 10 || size.height < 10 {
            if let parentFrame = parentElementFrame(element) {
                return parentFrame
            }
        }

        return CGRect(origin: position, size: size)
    }

    private func parentElementFrame(_ element: AXUIElement) -> CGRect? {
        var parentValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success else {
            return nil
        }

        let parent = parentValue as! AXUIElement

        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(parent, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(parent, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }
}

// MARK: - Highlight View

class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let fillColor = NSColor.systemBlue.withAlphaComponent(0.15)
        let strokeColor = NSColor.systemBlue.withAlphaComponent(0.8)

        fillColor.setFill()
        dirtyRect.fill()

        strokeColor.setStroke()
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 2
        borderPath.stroke()
    }
}
