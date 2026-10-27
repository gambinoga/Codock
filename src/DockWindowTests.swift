import AppKit

// Uses temporary state and no live reader, hook, real Codex navigation or settings.
func runDockWindowTests() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    precondition(!NSScreen.screens.isEmpty, "Window tests require a macOS WindowServer session")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = Project(id: "test", name: "DEMO", roots: ["/tmp/demo"], palette: 0)
    try! JSONEncoder().encode(DockConfiguration(projects: [project])).write(to: root.appendingPathComponent("configuration.json"))
    let owner = AppDelegate()
    owner.model = Model(resources: root, data: root)
    let primary = DockController(model: owner.model, placement: DockPlacement(mode: .visible), application: owner)
    owner.docks = [primary]
    defer { owner.docks.forEach { $0.dispose() } }
    owner.duplicate(primary)
    precondition(owner.docks.count == 2)
    let copy = owner.docks[1]
    precondition(primary.model === copy.model, "Clones must share one task model/reader")
    precondition(primary.placement.id != copy.placement.id)
    primary.showTasks(project)
    precondition(primary.selected == project.id && copy.selected == nil, "Popover selection belongs to its own bar")
    copy.showTasks(project)
    primary.closeTasks()
    precondition(copy.taskPanel != nil && copy.selected == project.id, "Closing one bar's list must not close the other bar's list")
    copy.setMode(.hidden)
    precondition(primary.mode == .visible && copy.mode == .hidden, "Visibility is independent")
    let task = TaskInfo(id: "conversation", project: project.id, title: "Synthetic task", turn: "one", status: "inProgress", started: 10, completed: 0)
    owner.model.apply(Snapshot(connected: true, tasks: [task], inputMonitoring: false, error: nil))
    let done = TaskInfo(id: task.id, project: project.id, title: task.title, turn: task.turn, status: "completed", started: 10, completed: 20)
    owner.model.apply(Snapshot(connected: true, tasks: [done], inputMonitoring: false, error: nil))
    precondition(primary.model.summary(project.id).done == 1 && copy.model.summary(project.id).done == 1)
    copy.model.dismiss(done)
    precondition(primary.model.summary(project.id).done == 0 && copy.model.recent(project.id).count == 1, "Reading on one bar updates all clones")
    owner.persistPlacements()
    let restored = Model(resources: root, data: root)
    precondition(restored.saved.restoredDocks == owner.docks.map { $0.placement }, "All live bar placements are persisted")
    owner.remove(primary)
    precondition(owner.docks.count == 1 && primary.panel == nil)
    owner.remove(copy)
    precondition(owner.docks.count == 1, "Closing a bar must keep the last remaining dock")
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    print("Multi-dock window lifecycle, selection, visibility, shared acknowledgements and persistence checks passed")
}
