import AppKit
import Carbon
import SwiftUI

// One application, one reader and shared task state; each dock owns its UI state.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: Model!
    var docks: [DockController] = []
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var hotkey: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?
    private var shortcutAvailable = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notifs")
        model = Model(resources: Bundle.main.resourceURL!, data: data)
        model.didOpenTask = { [weak self] in self?.docks.forEach { $0.closeTasks() } }
        model.didReceiveEvents = { [weak self] ids in self?.docks.forEach { $0.peek(ids) } }
        model.didFallbackOpen = { [weak self] project, message in
            self?.docks.forEach { $0.showNavigationHint(message, project: project) }
        }
        model.didChangeConfiguration = { [weak self] in
            self?.docks.forEach { $0.closeTasks(); $0.refresh(animated: false) }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Codock")
        statusItem.button?.toolTip = "Codock — Codex projects"
        registerShortcut()
        for placement in model.saved.restoredDocks {
            docks.append(DockController(model: model, placement: placement, application: self))
        }
        refreshMenu()
        model.start()
        if model.projects.isEmpty { showSettings() }
    }
    func refreshMenu() {
        guard let statusItem else { return }
        if docks.contains(where: { $0.menuShowing }) { return }
        statusItem.menu = docks.first?.contextMenu()
    }
    func persistPlacements() {
        var saved = model.saved
        saved.docks = docks.map { $0.placement }
        // Preserve the primary placement for compatibility with older local builds.
        if let primary = docks.first?.placement {
            saved.edge = primary.edge; saved.offset = primary.offset
            saved.mode = primary.mode; saved.screenID = primary.screenID
        }
        model.saved = saved
        model.persist()
    }
    func duplicate(_ source: DockController) {
        let screens = NSScreen.screens.map { source.screenIdentity($0) }
        let placement = source.placement.duplicate(on: screens, currentScreen: source.screenIdentity(source.screen))
        let copy = DockController(model: model, placement: placement, application: self)
        docks.append(copy)
        persistPlacements(); copy.refresh(animated: false); refreshMenu()
    }
    func remove(_ dock: DockController) {
        guard docks.count > 1 else { return }
        docks.removeAll { $0 === dock }
        dock.dispose()
        persistPlacements(); refreshMenu()
    }
    @objc func toggleShown() {
        let next: DockMode = docks.contains { $0.hidden } ? .visible : .hidden
        docks.forEach { $0.setMode(next) }
    }
    func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.toggleShown() }
            return noErr
        }, 1, &event, pointer, &hotkeyHandler)
        let identifier = EventHotKeyID(signature: 0x4E544653, id: 1)
        shortcutAvailable = status == noErr && RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
    @objc func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Codock — Projects"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProjectSettings(model: model, shortcutAvailable: shortcutAvailable))
        settingsWindow = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        docks.forEach { $0.setMode(.visible) }; return true
    }
    @objc func restartApp() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"", "codock-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        do { try helper.run(); NSApp.terminate(nil) }
        catch { NSAlert(error: error).runModal() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler) }
        docks.forEach { $0.dispose() }
    }
}
