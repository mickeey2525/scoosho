import AppKit
import ApplicationServices

/// Web App対応の深掘り要素選択。
/// AX子要素を再帰的に探索して最小要素を検出し、
/// スクロールで親↔子を切り替えてキャプチャ範囲を調整できる。
final class DeepElementPicker {
    private var overlayWindow: NSWindow?
    private var eventMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var scrollMonitor: Any?
    private var currentFrame: CGRect = .zero
    private var completion: ((CGRect?) -> Void)?

    private var elementHierarchy: [AXUIElement] = []
    private var currentDepthIndex: Int = 0
    private var lastMousePoint: CGPoint = .zero

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

        let highlightView = DeepHighlightView(frame: .zero)
        window.contentView = highlightView

        self.overlayWindow = window
    }

    private func updateOverlay(frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        currentFrame = frame

        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let cocoaY = screen.frame.maxY - frame.origin.y - frame.height
        let windowFrame = CGRect(x: frame.origin.x, y: cocoaY, width: frame.width, height: frame.height)

        overlayWindow?.setFrame(windowFrame, display: false)
        if let view = overlayWindow?.contentView as? DeepHighlightView {
            view.depthLabel = "\(currentDepthIndex + 1)/\(elementHierarchy.count)"
            view.setNeedsDisplay(view.bounds)
        }
        overlayWindow?.orderFront(nil)
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
    }

    // MARK: - Event Monitoring

    private func startMonitoring() {
        NSCursor.crosshair.push()

        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
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

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event: event)
        }

        let localMouseMove = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event: event)
            return event
        }
        objc_setAssociatedObject(self, "deepLocalMouseMove", localMouseMove, .OBJC_ASSOCIATION_RETAIN)

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
        objc_setAssociatedObject(self, "deepLocalClick", localClick, .OBJC_ASSOCIATION_RETAIN)

        let localScroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event: event)
            return nil
        }
        objc_setAssociatedObject(self, "deepLocalScroll", localScroll, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: - Mouse Move

    private func handleMouseMove(event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let axPoint = CGPoint(x: mouseLocation.x, y: screen.frame.maxY - mouseLocation.y)
        lastMousePoint = axPoint

        rebuildHierarchy(at: axPoint)

        if let frame = frameForCurrentDepth() {
            updateOverlay(frame: frame)
        }
    }

    // MARK: - Scroll Navigation

    private func handleScroll(event: NSEvent) {
        let delta = event.scrollingDeltaY

        if delta > 0 {
            // Scroll up -> parent (larger)
            if currentDepthIndex > 0 {
                currentDepthIndex -= 1
            }
        } else if delta < 0 {
            // Scroll down -> child (smaller)
            if currentDepthIndex < elementHierarchy.count - 1 {
                currentDepthIndex += 1
            }
        } else {
            return
        }

        if let frame = frameForCurrentDepth() {
            updateOverlay(frame: frame)
        }
    }

    // MARK: - Selection

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
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }

        for key in ["deepLocalMouseMove", "deepLocalClick", "deepLocalScroll"] {
            if let monitor = objc_getAssociatedObject(self, key) {
                NSEvent.removeMonitor(monitor)
                objc_setAssociatedObject(self, key, nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }

        overlayWindow = nil
        elementHierarchy = []
    }

    // MARK: - Accessibility Hierarchy

    private func rebuildHierarchy(at point: CGPoint) {
        let systemWide = AXUIElementCreateSystemWide()

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let leaf = element else {
            elementHierarchy = []
            currentDepthIndex = 0
            return
        }

        let deepest = findDeepestChild(of: leaf, containing: point, maxDepth: 30)

        // Walk up from deepest to window
        var hierarchy: [AXUIElement] = []
        var current: AXUIElement? = deepest

        while let el = current {
            if let frame = axFrame(of: el), frame.width >= 2, frame.height >= 2 {
                hierarchy.append(el)
            }

            var role: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            if let roleStr = role as? String, roleStr == kAXWindowRole as String {
                break
            }

            var parentValue: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentValue) == .success {
                current = (parentValue as! AXUIElement)
            } else {
                break
            }
        }

        // Reverse: index 0 = window (largest), last = deepest (smallest)
        hierarchy.reverse()

        // Deduplicate consecutive same-frame elements
        var deduped: [AXUIElement] = []
        var lastFrame: CGRect?
        for el in hierarchy {
            let frame = axFrame(of: el)
            if frame != lastFrame {
                deduped.append(el)
                lastFrame = frame
            }
        }

        elementHierarchy = deduped
        currentDepthIndex = max(0, deduped.count - 1)
    }

    private func findDeepestChild(of element: AXUIElement, containing point: CGPoint, maxDepth: Int) -> AXUIElement {
        guard maxDepth > 0 else { return element }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement], !children.isEmpty else {
            return element
        }

        var bestChild: AXUIElement?
        var bestArea: CGFloat = .greatestFiniteMagnitude

        for child in children {
            guard let frame = axFrame(of: child),
                  frame.contains(point),
                  frame.width >= 2, frame.height >= 2 else { continue }

            let area = frame.width * frame.height
            if area < bestArea {
                bestArea = area
                bestChild = child
            }
        }

        if let best = bestChild {
            return findDeepestChild(of: best, containing: point, maxDepth: maxDepth - 1)
        }

        return element
    }

    private func frameForCurrentDepth() -> CGRect? {
        guard currentDepthIndex >= 0, currentDepthIndex < elementHierarchy.count else { return nil }
        return axFrame(of: elementHierarchy[currentDepthIndex])
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
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

        return CGRect(origin: position, size: size)
    }
}

// MARK: - Highlight View with depth indicator

private class DeepHighlightView: NSView {
    var depthLabel: String = ""

    override func draw(_ dirtyRect: NSRect) {
        let fillColor = NSColor.systemOrange.withAlphaComponent(0.15)
        let strokeColor = NSColor.systemOrange.withAlphaComponent(0.8)

        fillColor.setFill()
        dirtyRect.fill()

        strokeColor.setStroke()
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw depth indicator badge
        if !depthLabel.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: depthLabel, attributes: attrs)
            let textSize = text.size()
            let padding: CGFloat = 4
            let badgeRect = CGRect(
                x: bounds.maxX - textSize.width - padding * 2 - 2,
                y: bounds.maxY - textSize.height - padding * 2 - 2,
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )

            NSColor.systemOrange.withAlphaComponent(0.9).setFill()
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
            badgePath.fill()

            text.draw(at: CGPoint(x: badgeRect.minX + padding, y: badgeRect.minY + padding))
        }
    }
}
