import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
@Observable
final class NotchController {
    private(set) var expandedDisplay: CGDirectDisplayID?
    private(set) var hoverDisplay: CGDirectDisplayID?
    let browser: NotchBrowserStore
    @ObservationIgnored private let settings: BotchSettings

    @ObservationIgnored private var panels: [CGDirectDisplayID: NotchPanel] = [:]
    @ObservationIgnored private var collapsedSizes: [CGDirectDisplayID: CGSize] = [:]
    @ObservationIgnored private var builtinDisplayID: CGDirectDisplayID?
    @ObservationIgnored private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var spaceObserver: NSObjectProtocol?
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private var moveMonitorGlobal: Any?
    @ObservationIgnored private var moveMonitorLocal: Any?
    @ObservationIgnored private var interactionRects: [CGDirectDisplayID: CGRect] = [:]
    @ObservationIgnored private var pointerInsideInterest = false
    @ObservationIgnored private var gateDisplay: CGDirectDisplayID?
    @ObservationIgnored private var gate = NotchHoverGate(
        openDwell: NotchController.openDwell, closeGrace: NotchHidePolicy.browser.closeGrace)
    @ObservationIgnored private var gateWorkItem: DispatchWorkItem?
    @ObservationIgnored private var collapseWorkItem: DispatchWorkItem?
    @ObservationIgnored private var panelSettleWorkItem: DispatchWorkItem?

    static let openDwell: TimeInterval = 0.1
    static let panelSettleDelay: TimeInterval = 0.45
    static let hidePolicy = NotchHidePolicy.browser

    init(browser: NotchBrowserStore, settings: BotchSettings) {
        self.browser = browser
        self.settings = settings
        browser.screenSize = { [weak self] in self?.browserScreenSize() }
        browser.onSizeChange = { [weak self] in self?.syncFrames() }
        browser.requestKeyFocus = { [weak self] in self?.makeExpandedPanelKey() }
        rebuildPanels()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateFullScreenVisibility() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                Task { @MainActor in self?.updateFullScreenVisibility() }
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.handleGlobalClick() }
        }
        startMoveMonitor()
    }

    func shutdown() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        stopMoveMonitor()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        panelSettleWorkItem?.cancel()
        panelSettleWorkItem = nil
        gateWorkItem?.cancel()
        gateWorkItem = nil
        expandedDisplay = nil
        browser.screenSize = { nil }
        browser.onSizeChange = nil
        browser.requestKeyFocus = nil
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        collapsedSizes.removeAll()
    }

    func rebuildPanels() {
        let builtin = NSScreen.screens.first {
            $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }
        builtinDisplayID = builtin?.displayID
        var wanted: Set<CGDirectDisplayID> = []
        if let builtin, let id = builtin.displayID {
            wanted.insert(id)
            placePanel(on: builtin, id: id)
        }
        if settings.showOnExternal || builtin == nil {
            for screen in NSScreen.screens {
                guard let id = screen.displayID, id != builtinDisplayID else { continue }
                wanted.insert(id)
                placePanel(on: screen, id: id)
            }
        }
        for id in panels.keys where !wanted.contains(id) {
            if expandedDisplay == id { collapseNow() }
            panels.removeValue(forKey: id)?.orderOut(nil)
            collapsedSizes.removeValue(forKey: id)
        }
        refreshInteractionRects()
        updateFullScreenVisibility()
    }

    private func refreshInteractionRects() {
        var rects: [CGDirectDisplayID: CGRect] = [:]
        for (id, panel) in panels {
            let margin = Self.hidePolicy.trackingMargin
            rects[id] = panel.frame.insetBy(dx: -margin, dy: -margin)
        }
        interactionRects = rects
    }

    private static let managedDisplaySpaces: () -> [[String: Any]]? = {
        guard let handle = dlopen(nil, RTLD_NOW),
            let defaultConnection = dlsym(handle, "_CGSDefaultConnection"),
            let copySpaces = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return { nil } }
        typealias ConnectionFn = @convention(c) () -> Int32
        typealias CopyFn = @convention(c) (Int32) -> CFArray?
        let connectionFn = unsafeBitCast(defaultConnection, to: ConnectionFn.self)
        let copyFn = unsafeBitCast(copySpaces, to: CopyFn.self)
        return { copyFn(connectionFn()) as? [[String: Any]] }
    }()

    private func isFullScreenSpace(_ screen: NSScreen) -> Bool {
        guard let id = screen.displayID,
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let uuidString = CFUUIDCreateString(nil, uuid) as String?,
            let displays = Self.managedDisplaySpaces()
        else { return false }
        for display in displays {
            guard (display["Display Identifier"] as? String) == uuidString,
                let current = display["Current Space"] as? [String: Any],
                let type = current["type"] as? Int
            else { continue }
            return type == 4
        }
        return false
    }

    private func updateFullScreenVisibility() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let panel = panels[id] else { continue }
            let fullScreen = isFullScreenSpace(screen)
            if fullScreen {
                fullScreenDisplays.insert(id)
                if expandedDisplay == id { collapseNow() }
            } else {
                fullScreenDisplays.remove(id)
            }
            panel.alphaValue = fullScreen ? 0 : 1
        }
        syncFrames()
    }

    private func placePanel(on screen: NSScreen, id: CGDirectDisplayID) {
        let base = NotchGeometry.collapsedSize(
            screenWidth: screen.frame.width,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            safeAreaTop: screen.safeAreaInsets.top)
        collapsedSizes[id] = base
        let panel = panels[id] ?? makePanel(id: id)
        if let host = panel.contentView?.subviews.first as? NSHostingView<AnyView> {
            host.rootView = AnyView(
                NotchContentView(controller: self, displayID: id, collapsedBase: base))
        }
        applyExactFrame(panel, screen: screen, id: id)
        updateInteractiveShape(panel, id: id)
    }

    private func makePanel(id: CGDirectDisplayID) -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        panel.collectionBehavior = [
            .fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle,
        ]
        let container = NotchCatcherView()
        let host = NotchHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panels[id] = panel
        panel.orderFrontRegardless()
        return panel
    }

    private func targetShapeSize(for id: CGDirectDisplayID) -> CGSize {
        let base = collapsedSizes[id] ?? NotchGeometry.fallbackSize
        guard expandedDisplay == id else { return base }
        return NotchGeometry.expandedShapeSize(
            browserSize: browserSize(on: id), notchHeight: base.height)
    }

    private func applyExactFrame(_ panel: NSPanel, screen: NSScreen, id: CGDirectDisplayID) {
        applyFrame(
            panel, screen: screen, size: NotchGeometry.panelSize(forShape: panelShape(for: id)))
    }

    private func applyFrame(_ panel: NSPanel, screen: NSScreen, size: CGSize) {
        panel.setFrame(
            NSRect(
                origin: NotchGeometry.origin(screenFrame: screen.frame, panelSize: size),
                size: size),
            display: true)
    }

    private func panelShape(for id: CGDirectDisplayID) -> CGSize {
        let notchHeight = (collapsedSizes[id] ?? NotchGeometry.fallbackSize).height
        return NotchGeometry.expandedShapeSize(
            browserSize: browserSize(on: id), notchHeight: notchHeight)
    }

    func browserSize(on id: CGDirectDisplayID) -> CGSize {
        NotchBrowserGeometry.clamp(browser.size, screen: browserArea(on: id))
    }

    private func browserArea(on id: CGDirectDisplayID?) -> CGSize? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else {
            return nil
        }
        let notchHeight = (id.flatMap { collapsedSizes[$0] } ?? NotchGeometry.fallbackSize).height
        return NotchBrowserGeometry.available(screen: screen.frame.size, notchHeight: notchHeight)
    }

    private func browserScreenSize() -> CGSize? {
        browserArea(on: expandedDisplay ?? builtinDisplayID ?? panels.keys.first)
    }

    private func updatePanelFrames() {
        var settling = false
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let panel = panels[id] else { continue }
            let wanted = NotchGeometry.panelSize(forShape: panelShape(for: id))
            let grown = NotchGeometry.union(panel.frame.size, wanted)
            if grown != panel.frame.size { applyFrame(panel, screen: screen, size: grown) }
            if grown != wanted { settling = true }
        }
        panelSettleWorkItem?.cancel()
        panelSettleWorkItem = nil
        refreshInteractionRects()
        guard settling else { return }
        let work = DispatchWorkItem { [weak self] in self?.settlePanelFrames() }
        panelSettleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.panelSettleDelay, execute: work)
    }

    private func settlePanelFrames() {
        panelSettleWorkItem = nil
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let panel = panels[id] else { continue }
            let wanted = NotchGeometry.panelSize(forShape: panelShape(for: id))
            if panel.frame.size != wanted { applyFrame(panel, screen: screen, size: wanted) }
        }
        refreshInteractionRects()
    }

    private func updateKeyFocus() {
        for (id, panel) in panels {
            let accepts = expandedDisplay == id
            panel.acceptsKeyFocus = accepts
            panel.keyEquivalentHandler =
                accepts
                ? { [weak self] event in self?.browser.handleKeyEquivalent(event) ?? false } : nil
            guard !accepts, panel.isKeyWindow else { continue }
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func makeExpandedPanelKey() {
        guard let id = expandedDisplay, let panel = panels[id], panel.acceptsKeyFocus else {
            return
        }
        panel.makeKey()
    }

    private func syncFrames() {
        updatePanelFrames()
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let panel = panels[id] else { continue }
            updateInteractiveShape(panel, id: id)
        }
        updateKeyFocus()
        refreshMouseTransparency()
    }

    private func updateInteractiveShape(_ panel: NSPanel, id: CGDirectDisplayID) {
        guard let catcher = panel.contentView as? NotchCatcherView else { return }
        let shape = targetShapeSize(for: id)
        guard catcher.interactiveShapeSize != shape else { return }
        catcher.interactiveShapeSize = shape
        refreshMouseTransparency()
    }

    private func refreshMouseTransparency() {
        let cursor = NSEvent.mouseLocation
        for (id, panel) in panels {
            let allowMouse =
                expandedDisplay == id
                && NotchGeometry.expandedAcceptsPointer(
                    cursor, shapeFrame: shapeFrame(of: panel),
                    buttonPressed: NSEvent.pressedMouseButtons != 0,
                    heldOpen: browser.holdsOpen)
            let ignores = fullScreenDisplays.contains(id) || !allowMouse
            if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
        }
    }

    private func optionSatisfied() -> Bool {
        !settings.requireOption || NSEvent.modifierFlags.contains(.option)
    }

    var isExpanded: Bool { expandedDisplay != nil }

    func isExpanded(on id: CGDirectDisplayID) -> Bool { expandedDisplay == id }

    func isHovering(on id: CGDirectDisplayID) -> Bool { hoverDisplay == id }

    func openBrowser() {
        let point = NSEvent.mouseLocation
        let under = panels.keys.first { id in
            NSScreen.screens.first { $0.displayID == id }?.frame.contains(point) ?? false
        }
        guard let id = under ?? builtinDisplayID ?? panels.keys.first else { return }
        expand(on: id)
        makeExpandedPanelKey()
    }

    func expand(on id: CGDirectDisplayID) {
        collapseWorkItem?.cancel()
        gateWorkItem?.cancel()
        gateWorkItem = nil
        gate.forceOpen()
        gateDisplay = id
        guard expandedDisplay != id else { return }
        hoverDisplay = nil
        expandedDisplay = id
        syncFrames()
    }

    func collapseNow() {
        guard isExpanded else { return }
        expandedDisplay = nil
        gate.forceClosed()
        gateWorkItem?.cancel()
        gateWorkItem = nil
        syncFrames()
    }

    func hoverChanged(_ hovering: Bool, on id: CGDirectDisplayID?) {
        let next = hovering && !isExpanded ? id : nil
        if hoverDisplay != next { hoverDisplay = next }
        guard !isExpanded else { return }
        applyProximity(hovering ? .open : .outside, on: id)
    }

    private func monotonicNow() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func applyProximity(_ raw: NotchProximity, on id: CGDirectDisplayID?) {
        var proximity = raw
        if !gate.isOpen, proximity == .open, !(settings.openOnHover && optionSatisfied()) {
            proximity = .outside
        }
        if proximity != .outside, let id { gateDisplay = id }
        handleGate(gate.sample(proximity, now: monotonicNow()))
    }

    private func handleGate(_ transition: NotchGateTransition) {
        switch transition {
        case .schedule(let deadline):
            gateWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.fireGate() }
            gateWorkItem = work
            let delay = max(0, deadline - monotonicNow())
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        case .cancelPending:
            gateWorkItem?.cancel()
            gateWorkItem = nil
        case .none, .opened, .closed:
            break
        }
    }

    private func fireGate() {
        gateWorkItem = nil
        let transition = gate.fire(now: monotonicNow())
        switch transition {
        case .opened:
            if let gateDisplay { expand(on: gateDisplay) }
        case .closed:
            if browser.holdsOpen {
                gate.forceOpen()
            } else {
                collapseNow()
            }
        case .schedule:
            handleGate(transition)
        case .none, .cancelPending:
            break
        }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        let inside = interactionRects.values.contains { $0.contains(point) }
        if !inside, !pointerInsideInterest { return }
        pointerInsideInterest = inside
        refreshMouseTransparency()
        if let expandedDisplay, let frames = frames(for: expandedDisplay) {
            applyProximity(
                NotchGeometry.proximity(
                    point: point, collapsedFrame: frames.collapsed,
                    expandedFrame: frames.expanded, keepInset: Self.hidePolicy.keepInset),
                on: expandedDisplay)
        } else {
            let id = notchDisplay(near: point)
            let near =
                id.flatMap { frames(for: $0) }
                .map { NotchGeometry.openFrame(around: $0.collapsed).contains(point) } ?? false
            hoverChanged(near, on: id)
        }
    }

    private func notchDisplay(near point: CGPoint) -> CGDirectDisplayID? {
        panels.keys.first { id in
            guard let frames = frames(for: id) else { return false }
            return NotchGeometry.interactionFrame(around: frames.collapsed).contains(point)
        }
    }

    private func frames(for id: CGDirectDisplayID) -> (collapsed: CGRect, expanded: CGRect)? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == id })
        else { return nil }
        let collapsedSize = collapsedSizes[id] ?? NotchGeometry.fallbackSize
        let collapsed = CGRect(
            origin: NotchGeometry.origin(screenFrame: screen.frame, panelSize: collapsedSize),
            size: collapsedSize)
        let expandedSize = NotchGeometry.expandedShapeSize(
            browserSize: browserSize(on: id), notchHeight: collapsedSize.height)
        let expanded = CGRect(
            origin: NotchGeometry.origin(screenFrame: screen.frame, panelSize: expandedSize),
            size: expandedSize)
        return (collapsed, expanded)
    }

    private func startMoveMonitor() {
        guard moveMonitorGlobal == nil else { return }
        moveMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }
        moveMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
            return event
        }
    }

    private func stopMoveMonitor() {
        if let moveMonitorGlobal { NSEvent.removeMonitor(moveMonitorGlobal) }
        if let moveMonitorLocal { NSEvent.removeMonitor(moveMonitorLocal) }
        moveMonitorGlobal = nil
        moveMonitorLocal = nil
    }

    private func handleGlobalClick() {
        let point = NSEvent.mouseLocation
        guard !isExpanded, let id = notchDisplay(near: point), let frames = frames(for: id),
            NotchGeometry.openFrame(around: frames.collapsed).contains(point), optionSatisfied()
        else { return }
        expand(on: id)
    }

    private func shapeFrame(of panel: NSPanel) -> CGRect {
        guard let catcher = panel.contentView as? NotchCatcherView,
            let shape = catcher.interactiveShapeSize
        else { return panel.frame }
        return CGRect(
            x: panel.frame.midX - shape.width / 2, y: panel.frame.maxY - shape.height,
            width: shape.width, height: shape.height)
    }

    var panelForTesting: NSPanel? {
        (expandedDisplay ?? builtinDisplayID ?? panels.keys.first).flatMap { panels[$0] }
    }
}

@MainActor
final class NotchHostingView: NSHostingView<AnyView> {
    override func cursorUpdate(with event: NSEvent) {}
}

@MainActor
final class NotchCatcherView: NSView {
    var interactiveShapeSize: CGSize?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let shape = interactiveShapeSize else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let rect = CGRect(
            x: (bounds.width - shape.width) / 2, y: bounds.height - shape.height,
            width: shape.width, height: shape.height)
        guard rect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func cursorUpdate(with event: NSEvent) {}
}
