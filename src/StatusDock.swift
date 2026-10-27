import AppKit
import SwiftUI
import Combine
import Carbon

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// A single native input surface owns the complete press/drag/release sequence.
// Avatars are drawn here, so dragging from their labels never triggers a click.
final class DockSurface: NSView {
    weak var owner: DockController?
    var isTab = false
    private var tracking: NSTrackingArea?
    private var start: NSPoint?
    private var startFrame: NSRect?
    private var pressed: Int?
    private var dragged = false
    private var accessibilityButtons: [AvatarAccessibility] = []
    private var scrollOffset: CGFloat = 0
    private var loadingRings: [String: LoadingRingView] = [:]
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    func avatarRect(_ index: Int) -> NSRect {
        guard let owner else { return .zero }
        return owner.edge.vertical ? NSRect(x: 10, y: 12 + CGFloat(index) * 58 - scrollOffset, width: 44, height: 44)
            : NSRect(x: 12 + CGFloat(index) * 58 - scrollOffset, y: 10, width: 44, height: 44)
    }
    func reveal(_ id: String) {
        guard let owner, let index = owner.model.projects.firstIndex(where: { $0.id == id }) else { return }
        let rect = avatarRect(index)
        let start = owner.edge.vertical ? rect.minY : rect.minX
        let end = owner.edge.vertical ? rect.maxY : rect.maxX
        let length = owner.edge.vertical ? bounds.height : bounds.width
        if start < 10 { scrollOffset = max(0, scrollOffset + start - 12) }
        else if end > length - 10 { scrollOffset += end - length + 12 }
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard !isTab, let owner else { return }
        let length = owner.edge.vertical ? bounds.height : bounds.width
        let content = DockGeometry.size(count: owner.model.projects.count, edge: owner.edge)
        let maximum = max(0, (owner.edge.vertical ? content.height : content.width) - length)
        guard maximum > 0 else { return }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        scrollOffset = min(maximum, max(0, scrollOffset - delta * (event.hasPreciseScrollingDeltas ? 1 : 16)))
        owner.closeTasks(); owner.hovered = nil; owner.updateTooltip()
        needsDisplay = true; refreshAccessibility()
    }
    override func layout() {
        super.layout()
        guard let owner, !isTab else { return }
        let content = DockGeometry.size(count: owner.model.projects.count, edge: owner.edge)
        scrollOffset = min(scrollOffset, max(0, (owner.edge.vertical ? content.height - bounds.height : content.width - bounds.width)))
    }
    func index(at event: NSEvent) -> Int? {
        guard let owner else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return owner.model.projects.indices.first { avatarRect($0).insetBy(dx: -5, dy: -5).contains(point) }
    }
    func refreshAccessibility() {
        guard let owner else { return }
        setAccessibilityElement(false)
        if isTab {
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Show Codock")
            return
        }
        accessibilityButtons = owner.model.projects.indices.filter { bounds.intersects(avatarRect($0)) }.map { index in
            let project = owner.model.projects[index]
            let item = AvatarAccessibility()
            item.action = { [weak owner] in owner?.activate(project) }
            item.setAccessibilityRole(.button)
            item.setAccessibilityEnabled(true)
            item.setAccessibilityLabel(project.name)
            item.setAccessibilityValue(owner.model.summary(project.id).label)
            item.setAccessibilityParent(self)
            let local = avatarRect(index)
            item.setAccessibilityFrame(window?.convertToScreen(convert(local, to: nil)) ?? .zero)
            return item
        }
        setAccessibilityChildren(accessibilityButtons)
    }
    override func accessibilityPerformPress() -> Bool {
        guard isTab, let owner else { return false }
        owner.setMode(.visible)
        return true
    }
    override func mouseDown(with event: NSEvent) {
        if isTab { owner?.setMode(.visible); return }
        start = NSEvent.mouseLocation
        startFrame = window?.frame
        pressed = index(at: event)
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let owner, let start, let startFrame else { return }
        let point = NSEvent.mouseLocation
        if !dragged {
            guard DockGeometry.dragging(start: start, point: point) else { return }
            dragged = true
            owner.beginDrag()
        }
        owner.drag(to: point, start: start, frame: startFrame)
    }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; startFrame = nil; pressed = nil; dragged = false }
        guard start != nil, let owner else { return }
        if dragged { owner.endDrag() }
        else if let pressed, owner.model.projects.indices.contains(pressed) { owner.activate(owner.model.projects[pressed]) }
    }
    override func rightMouseDown(with event: NSEvent) { owner?.showContextMenu(event: event, view: self, project: isTab ? nil : index(at: event).flatMap { owner?.model.projects[$0] }) }
    override func mouseEntered(with event: NSEvent) {
        owner?.hoverEntered(tab: isTab)
        if !isTab { mouseMoved(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        guard !isTab else { return }
        let previous = owner?.hovered
        owner?.hovered = index(at: event).flatMap { owner?.model.projects[$0].id }
        if previous != owner?.hovered { needsDisplay = true }
        if owner?.hovered != nil { NSCursor.pointingHand.set() } else { NSCursor.openHand.set() }
        owner?.updateTooltip()
    }
    override func mouseExited(with event: NSEvent) { owner?.hoverExited(tab: isTab) }
    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: isTab ? 6 : 32, yRadius: isTab ? 6 : 32)
        owner.model.configuration.barColor.setFill(); path.fill()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke(); path.lineWidth = 0.5; path.stroke()
        if isTab {
            let statuses = owner.model.projects.map { owner.model.status($0.id) }
            if statuses.contains(where: { [.approval, .failed, .done].contains($0) }) {
                (statuses.contains(where: { $0 == .approval || $0 == .failed }) ? NSColor.hex("BA7517") : .hex("639922")).setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
            }
            return
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let projectIDs = Set(owner.model.projects.map { $0.id })
        for id in Array(loadingRings.keys) where !projectIDs.contains(id) {
            loadingRings.removeValue(forKey: id)?.removeFromSuperview()
        }
        for (index, project) in owner.model.projects.enumerated() {
            let rect = avatarRect(index)
            guard bounds.intersects(rect) else {
                loadingRings.removeValue(forKey: project.id)?.removeFromSuperview()
                continue
            }
            let summary = owner.model.summary(project.id)
            let status = summary.status
            let opening = owner.model.openingTask.map { key in key == "new:" + project.id || owner.model.visible(project.id).contains { $0.eventID == key } } == true
            let hovered = owner.hovered == project.id
            let alpha: CGFloat = status == .idle && !hovered && !opening ? 0.5 : 1
            NSColor.hex(project.colors[0]).withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            if hovered {
                NSColor.hex(project.colors[2]).withAlphaComponent(0.55).setStroke()
                let hoverRing = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                hoverRing.lineWidth = 1.5; hoverRing.stroke()
            }
            let text = project.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.hex(project.colors[1]).withAlphaComponent(alpha)]
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            var fitted = attrs
            let width = text.size(withAttributes: attrs).width
            fitted[.font] = NSFont.systemFont(ofSize: min(11, max(8, 11 * 38 / max(1, width))), weight: .medium)
            fitted[.paragraphStyle] = paragraph
            let textHeight = text.size(withAttributes: fitted).height
            text.draw(in: NSRect(x: rect.minX + 3, y: rect.midY - textHeight / 2, width: 38, height: textHeight + 1), withAttributes: fitted)
            let loading = summary.running > 0 || opening
            if loading {
                let ring: LoadingRingView
                if let existing = loadingRings[project.id] { ring = existing }
                else { ring = LoadingRingView(); loadingRings[project.id] = ring; addSubview(ring) }
                ring.frame = rect.insetBy(dx: -5, dy: -5)
                ring.configure(color: .hex(project.colors[2]), lineWidth: 2, fraction: 220.0 / 360, duration: 1, reduced: reduced)
                ring.excludedRect = nil
            } else {
                loadingRings.removeValue(forKey: project.id)?.removeFromSuperview()
                if status == .approval || status == .failed {
                    (status == .approval ? NSColor.hex("EF9F27") : .hex("E24B4A")).setStroke()
                    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -4, dy: -4)); ring.lineWidth = 2; ring.stroke()
                }
            }
            if summary.hasBadge {
                let symbol = (summary.badgeText ?? "") as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white]
                let textSize = symbol.size(withAttributes: attrs)
                let diameter: CGFloat = summary.priority == 1 && summary.topCount == 1 ? 11 : 14
                let width = max(diameter, textSize.width + (symbol.length > 0 ? 6 : 0))
                let badge = NSRect(x: rect.maxX - width + 3, y: rect.minY - 3, width: width, height: diameter)
                // Keep the composited ring behind the badge's opaque surround.
                if let ring = loadingRings[project.id] {
                    let cutout = badge.insetBy(dx: -2, dy: -2)
                    ring.excludedRect = NSRect(x: cutout.minX - ring.frame.minX, y: ring.frame.maxY - cutout.maxY, width: cutout.width, height: cutout.height)
                }
                let color = status == .approval ? NSColor.hex("BA7517") : status == .failed ? .hex("E24B4A") : status == .running ? .hex("888780") : .hex("639922")
                owner.model.configuration.barColor.setFill()
                NSBezierPath(roundedRect: badge.insetBy(dx: -2, dy: -2), xRadius: (diameter + 4) / 2, yRadius: (diameter + 4) / 2).fill()
                color.setFill(); NSBezierPath(roundedRect: badge, xRadius: diameter / 2, yRadius: diameter / 2).fill()
                symbol.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2), withAttributes: attrs)
            }
            if (owner.peekProjects.contains(project.id) && owner.peeking) || owner.selected == project.id {
                NSColor.hex(project.colors[2]).setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -8, dy: -8)); ring.lineWidth = 2; ring.stroke()
            }
        }
    }
}
final class TaskHostingView: NSHostingView<TasksPanel> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class AvatarAccessibility: NSAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { action?(); return true }
}

final class DockController: NSObject, NSMenuDelegate {
    weak var application: AppDelegate?
    var placement: DockPlacement
    var selected: String?
    var model: Model!
    var panel: FloatingPanel!
    var tab: FloatingPanel!
    var tooltip: FloatingPanel!
    var ghost: FloatingPanel!
    var surface: DockSurface!
    var tabSurface: DockSurface!
    var taskPanel: FloatingPanel?
    var edge: DockEdge { placement.edge }
    var mode: DockMode { placement.mode }
    var offset: Double { placement.offset }
    var hovered: String?
    var peekProjects = Set<String>()
    var peeking = false
    private var hoverPeek = false
    private var navigationHint: String?
    private var isDragging = false
    private var releaseToHide = false
    private var menuOpen = false
    private var isHidden = false
    private var animationGeneration = 0
    private var subscriptions = Set<AnyCancellable>()
    private var tuck: DispatchWorkItem?
    private var peekEnd: DispatchWorkItem?
    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var screenObserverMotion: NSObjectProtocol?
    var screen: NSScreen {
        NSScreen.screens.first { screenIdentity($0) == placement.screenID } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func screenIdentity(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "main") }
    func makePanel() -> FloatingPanel {
        let window = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.hidesOnDeactivate = false; window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        return window
    }
    init(model: Model, placement: DockPlacement, application: AppDelegate) {
        self.model = model; self.placement = placement; self.application = application
        super.init()
        panel = makePanel(); tab = makePanel(); tooltip = makePanel(); ghost = makePanel()
        tooltip.ignoresMouseEvents = true; ghost.ignoresMouseEvents = true
        surface = DockSurface(); surface.owner = self; panel.contentView = surface
        tabSurface = DockSurface(); tabSurface.owner = self; tabSurface.isTab = true; tab.contentView = tabSurface
        for publisher in [model.$tasks.map { _ in () }.eraseToAnyPublisher(), model.$saved.map { _ in () }.eraseToAnyPublisher(), model.$openingTask.map { _ in () }.eraseToAnyPublisher(), model.$configuration.map { _ in () }.eraseToAnyPublisher()] {
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.closeTasks() }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            if let self {
                self.updateClickThrough()
                if event.type != .mouseMoved && event.window !== self.panel && event.window !== self.taskPanel { self.closeTasks() }
            }
            return event
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in self?.updateClickThrough() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh(animated: false) }
        screenObserverMotion = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.surface.needsDisplay = true }
        refresh(animated: false)
    }
    func dispose() {
        tuck?.cancel(); peekEnd?.cancel(); animationGeneration += 1
        subscriptions.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let screenObserverMotion { NSWorkspace.shared.notificationCenter.removeObserver(screenObserverMotion) }
        for monitor in [mouseMonitor, clickMonitor, localClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        closeTasks()
        for window in [panel, tab, tooltip, ghost].compactMap({ $0 }) { window.orderOut(nil) }
        panel.contentView = nil; tab.contentView = nil
        panel = nil; tab = nil; tooltip = nil; ghost = nil
    }
    func refresh(animated: Bool = true) {
        guard panel != nil, !isDragging else { return }
        let hidden = DockGeometry.hide(mode: mode, quiet: model.quiet, hover: hoverPeek, peek: peeking, interacting: menuOpen || taskPanel != nil)
        let changed = hidden != isHidden
        isHidden = hidden
        let target = DockGeometry.frame(screen: screen.visibleFrame, edge: edge, offset: offset, count: model.projects.count)
        let tabFrame = DockGeometry.frame(screen: screen.visibleFrame, edge: edge, offset: offset, count: model.projects.count, tab: true)
        tab.setFrame(tabFrame, display: true)
        tabSurface.needsDisplay = true; tabSurface.refreshAccessibility()
        animationGeneration += 1
        let generation = animationGeneration
        if hidden {
            tab.orderFrontRegardless()
            if changed && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    panel.animator().setFrame(DockGeometry.offscreen(target, edge: edge), display: true)
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in if self?.animationGeneration == generation { self?.panel.orderOut(nil) } }
            } else { panel.orderOut(nil) }
        } else {
            if changed { panel.setFrame(DockGeometry.offscreen(target, edge: edge), display: false); panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            if hoverPeek && mode != .visible { tab.orderFrontRegardless() } else { tab.orderOut(nil) }
            if changed && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    panel.animator().setFrame(target, display: true)
                    panel.animator().alphaValue = 1
                }
            } else { panel.setFrame(target, display: true); panel.alphaValue = 1 }
            surface.refreshAccessibility(); surface.needsDisplay = true
        }
        updateTooltip(); layoutTasks(); updateClickThrough()
        if !menuOpen { application?.refreshMenu() }
        writeDiagnostics()
    }
    func writeDiagnostics() {
        func rect(_ r: NSRect) -> [String: CGFloat] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
        var state: [String: Any] = ["edge": edge.rawValue, "mode": mode.rawValue, "hidden": isHidden, "bar": rect(panel.frame), "tab": rect(tab.frame), "listVisible": taskPanel != nil]
        if let list = taskPanel { state["list"] = rect(list.frame); state["overlapsBells"] = panel.frame.intersects(list.frame) }
        if let bytes = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? bytes.write(to: model.data.appendingPathComponent("panel-state-" + placement.id + ".json"), options: .atomic)
            if application?.docks.first === self { try? bytes.write(to: model.data.appendingPathComponent("panel-state.json"), options: .atomic) }
        }
    }
    func updateClickThrough() {
        guard panel != nil, !isDragging else { return }
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !NSBezierPath(roundedRect: NSRect(origin: .zero, size: panel.frame.size), xRadius: 32, yRadius: 32).contains(point)
    }
    func showNavigationHint(_ message: String, project: String) {
        navigationHint = message; peek([project])
    }
    func peek(_ ids: [String]) {
        let valid = ids.filter { id in model.projects.contains { $0.id == id } }
        guard !valid.isEmpty else { return }
        peekEnd?.cancel()
        peekProjects = Set(valid); peeking = true
        surface.reveal(valid[0])
        refresh()
        let work = DispatchWorkItem { [weak self] in self?.peeking = false; self?.peekProjects = []; self?.navigationHint = nil; self?.refresh() }
        peekEnd = work; DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
    func hoverEntered(tab: Bool) {
        tuck?.cancel()
        if tab { hoverPeek = true; refresh() }
    }
    func hoverExited(tab: Bool) {
        if !tab {
            hovered = nil
            surface.needsDisplay = true
            NSCursor.arrow.set()
            updateTooltip()
        }
        guard hoverPeek else { return }
        tuck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hoverPeek = false; self?.refresh() }
        tuck = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func setMode(_ mode: DockMode) {
        closeTasks()
        peekEnd?.cancel(); tuck?.cancel(); peeking = false; peekProjects = []; hoverPeek = false; hovered = nil
        placement.mode = mode; persistPlacement(); refresh()
    }
    var hidden: Bool { isHidden }
    var menuShowing: Bool { menuOpen }
    func persistPlacement() { application?.persistPlacements() }
    func beginDrag() {
        closeTasks(); tuck?.cancel(); hovered = nil; tooltip.orderOut(nil)
        isDragging = true; panel.ignoresMouseEvents = false
        NSCursor.closedHand.push()
    }
    func drag(to point: NSPoint, start: NSPoint, frame: NSRect) {
        let targetScreen = NSScreen.screens.first { $0.frame.contains(point) } ?? screen
        placement.screenID = screenIdentity(targetScreen)
        let nextEdge = DockGeometry.nearest(point, screen: targetScreen.visibleFrame)
        let wasVertical = frame.height > frame.width
        var fx = (start.x - frame.minX) / frame.width, fy = (start.y - frame.minY) / frame.height
        if wasVertical != nextEdge.vertical { swap(&fx, &fy) }
        placement.edge = nextEdge
        let size = DockGeometry.frame(screen: targetScreen.visibleFrame, edge: nextEdge, offset: offset, count: model.projects.count).size
        let moving = NSRect(x: point.x - min(1, max(0, fx)) * size.width, y: point.y - min(1, max(0, fy)) * size.height, width: size.width, height: size.height)
        panel.setFrame(moving, display: true)
        surface.needsDisplay = true
        placement.offset = DockGeometry.offset(frame: moving, screen: targetScreen.visibleFrame, edge: nextEdge)
        // macOS clamps the pointer to physical screen edges; crossing the dock's
        // center beyond that edge is represented by the pointer reaching its last 2pt.
        let outer = targetScreen.frame.insetBy(dx: 2, dy: 2)
        releaseToHide = !outer.contains(point)
        let proposed = DockGeometry.frame(screen: targetScreen.visibleFrame, edge: nextEdge, offset: offset, count: model.projects.count)
        let preview = SnapPreview(hidden: releaseToHide)
        ghost.contentView = NSHostingView(rootView: preview)
        let previewSize = releaseToHide ? NSSize(width: 164, height: 44) : (nextEdge.vertical ? NSSize(width: 8, height: proposed.height) : NSSize(width: proposed.width, height: 8))
        var rect = NSRect(origin: proposed.origin, size: previewSize)
        if nextEdge == .right { rect.origin.x = targetScreen.visibleFrame.maxX - previewSize.width - 4 }
        if nextEdge == .top { rect.origin.y = targetScreen.visibleFrame.maxY - previewSize.height - 4 }
        rect.origin.x = min(max(rect.minX, targetScreen.visibleFrame.minX + 4), targetScreen.visibleFrame.maxX - rect.width - 4)
        rect.origin.y = min(max(rect.minY, targetScreen.visibleFrame.minY + 4), targetScreen.visibleFrame.maxY - rect.height - 4)
        ghost.setFrame(rect, display: true); ghost.orderFrontRegardless()
    }
    func endDrag() {
        isDragging = false; ghost.orderOut(nil); NSCursor.pop()
        if releaseToHide { placement.mode = .hidden; hoverPeek = false; peeking = false }
        persistPlacement(); refresh()
    }
    func activate(_ project: Project) {
        guard model.openingTask == nil else { return }
        if let target = model.directTarget(project.id) { closeTasks(); model.open(target) { [weak self] in self?.showTasks(project) } }
        else if selected == project.id { closeTasks() }
        else { showTasks(project) }
    }
    func showTasks(_ requested: Project) {
        guard let project = model.projects.first(where: { $0.id == requested.id }) else { return }
        closeTasks(); hovered = nil; tooltip.orderOut(nil)
        selected = project.id
        let detail = makePanel()
        let frame = tasksFrame(project: project)
        detail.contentView = TaskHostingView(rootView: TasksPanel(model: model, project: project, panelSize: frame.size))
        detail.setFrame(frame, display: true)
        taskPanel = detail; panel.addChildWindow(detail, ordered: .above); detail.orderFrontRegardless()
        refresh()
    }
    func avatarFrame(_ project: Project) -> NSRect {
        guard let index = model.projects.firstIndex(where: { $0.id == project.id }) else { return panel.frame }
        let local = surface.avatarRect(index)
        return NSRect(x: panel.frame.minX + local.minX, y: panel.frame.maxY - local.maxY, width: local.width, height: local.height)
    }
    func tasksFrame(project: Project) -> NSRect {
        let size = ConversationLayout.size(active: model.conversations(project.id).count, recent: model.recent(project.id).count,
                                           hasError: model.openingError != nil || !model.connected)
        return ConversationLayout.frame(anchor: avatarFrame(project), screen: screen.visibleFrame, edge: edge, size: size)
    }
    func closeTasks() {
        if let taskPanel { panel?.removeChildWindow(taskPanel); taskPanel.orderOut(nil) }
        let hadList = taskPanel != nil
        taskPanel = nil; selected = nil
        if hadList { DispatchQueue.main.async { self.refresh() } }
    }
    func layoutTasks() {
        guard let detail = taskPanel, let project = model.projects.first(where: { $0.id == selected }) else { return }
        let frame = tasksFrame(project: project)
        detail.setFrame(frame, display: true)
        if let host = detail.contentView as? NSHostingView<TasksPanel>, host.rootView.panelSize != frame.size { host.rootView = TasksPanel(model: model, project: project, panelSize: frame.size) }
    }
    func updateTooltip() {
        let id = hovered ?? (peeking ? model.projects.first(where: { peekProjects.contains($0.id) })?.id : nil)
        guard !isHidden, !isDragging, !menuOpen, taskPanel == nil, let id,
              let index = model.projects.firstIndex(where: { $0.id == id }) else { tooltip?.orderOut(nil); return }
        let project = model.projects[index]
        let hint = navigationHint ?? model.directTarget(id).map { "Click to open “\($0.title)”" } ?? "Click to see conversations"
        let heading = project.name + " · " + model.summary(id).label
        let label = heading + "\n" + hint
        let field = NSTextField(wrappingLabelWithString: label)
        field.font = .systemFont(ofSize: 12)
        let attributed = NSMutableAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        attributed.addAttributes([.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor], range: NSRange(location: (heading as NSString).length + 1, length: (hint as NSString).length))
        field.attributedStringValue = attributed
        let textWidth = min(CGFloat(380), max(180, max((heading as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width, (hint as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width)))
        let textSize = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 300))
        let size = NSSize(width: textWidth + 20, height: max(40, textSize.height + 16))
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true; container.layer?.backgroundColor = NSColor.dockSurface.cgColor
        container.layer?.cornerRadius = 10; container.layer?.borderWidth = 0.5; container.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        field.frame = NSRect(x: 10, y: 8, width: textWidth, height: size.height - 16); container.addSubview(field)
        tooltip.contentView = container
        let target = ConversationLayout.frame(anchor: avatarFrame(project), screen: screen.visibleFrame, edge: edge, size: size)
        tooltip.setFrame(target, display: true); tooltip.orderFrontRegardless()
    }
    func contextMenu(project: Project? = nil) -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        let scopedCount = project.map { model.finished($0.id).count } ?? 0
        let allCount = model.finished().count
        if let project, scopedCount > 0 {
            let item = NSMenuItem(title: "Dismiss finished in \(project.name) (\(scopedCount))", action: #selector(dismissFinished(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = project.id; menu.addItem(item)
        }
        if allCount > 0 && allCount != scopedCount {
            let item = NSMenuItem(title: "Dismiss all finished (\(allCount))", action: #selector(dismissFinished(_:)), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        for (title, mode) in [("Hide now", DockMode.hidden), ("Auto-hide when quiet", .auto), ("Always visible", .visible)] {
            let item = NSMenuItem(title: title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue
            if mode == .hidden { item.keyEquivalent = "j"; item.keyEquivalentModifierMask = [.option, .command] }
            item.state = self.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show dock", action: #selector(showDock), keyEquivalent: ""); show.target = self; menu.addItem(show)
        let duplicate = NSMenuItem(title: "Duplicate dock", action: #selector(duplicateDock), keyEquivalent: ""); duplicate.target = self; menu.addItem(duplicate)
        if (application?.docks.count ?? 1) > 1 {
            let remove = NSMenuItem(title: "Close this dock", action: #selector(removeDock), keyEquivalent: ""); remove.target = self; menu.addItem(remove)
        }
        let reset = NSMenuItem(title: "Reset position", action: #selector(resetPosition), keyEquivalent: ""); reset.target = self; menu.addItem(reset)
        let settings = NSMenuItem(title: "Configure projects…", action: #selector(showSettings), keyEquivalent: ""); settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let restart = NSMenuItem(title: "Restart Codock", action: #selector(restartApp), keyEquivalent: ""); restart.target = self; menu.addItem(restart)
        let quit = NSMenuItem(title: "Quit Codock", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        return menu
    }
    func showContextMenu(event: NSEvent, view: NSView, project: Project? = nil) {
        closeTasks(); hovered = nil
        NSMenu.popUpContextMenu(contextMenu(project: project), with: event, for: view)
    }
    @objc func dismissFinished(_ sender: NSMenuItem) { model.dismissFinished(sender.representedObject as? String); refresh() }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; tooltip.orderOut(nil) }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; DispatchQueue.main.async { self.refresh() } }
    @objc func chooseMode(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let mode = DockMode(rawValue: raw) { setMode(mode) } }
    @objc func resetPosition() { closeTasks(); placement.edge = .right; placement.offset = 0.5; placement.screenID = screenIdentity(NSScreen.main ?? screen); persistPlacement(); refresh() }
    @objc func showSettings() { application?.showSettings() }
    @objc func showDock() { setMode(.visible) }
    @objc func duplicateDock() { application?.duplicate(self) }
    @objc func removeDock() { application?.remove(self) }
    @objc func restartApp() { application?.restartApp() }
    @objc func quit() { application?.quit() }

}
struct SnapPreview: View {
    let hidden: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            if hidden { Text("Release to hide").font(.system(size: 12)).foregroundColor(.primary) }
        }
    }
}
