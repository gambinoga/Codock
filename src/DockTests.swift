import AppKit

func runDockTests() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checks += 1 }
    let screen = NSRect(x: -1440, y: 40, width: 1440, height: 900)
    for edge in DockEdge.allCases {
        for count in [1, 4, 5, 20, 1000] {
            for offset in [-1.0, 0, 0.5, 1, 2, Double.nan] {
                let frame = DockGeometry.frame(screen: screen, edge: edge, offset: offset, count: count)
                check(screen.contains(frame), "Dock fits screen at any normalized offset")
                check(edge.vertical ? frame.width == 64 : frame.height == 64, "Edge determines orientation")
                let tab = DockGeometry.frame(screen: screen, edge: edge, offset: offset, count: count, tab: true)
                check(screen.contains(tab), "Hidden tab stays on its screen")
                check(edge.vertical ? tab.size == NSSize(width: 10, height: 64) : tab.size == NSSize(width: 64, height: 10), "Tab dimensions follow edge")
                let outside = DockGeometry.offscreen(frame, edge: edge)
                check(!outside.intersects(frame), "Hide target slides fully outside dock position")
            }
        }
    }
    check(DockGeometry.nearest(NSPoint(x: -1438, y: 400), screen: screen) == .left, "Left edge snap")
    check(DockGeometry.nearest(NSPoint(x: -2, y: 400), screen: screen) == .right, "Right edge snap")
    check(DockGeometry.nearest(NSPoint(x: -720, y: 938), screen: screen) == .top, "Top edge snap")
    check(DockGeometry.nearest(NSPoint(x: -720, y: 42), screen: screen) == .bottom, "Bottom edge snap")
    check(DockGeometry.hide(mode: .auto, quiet: true, hover: false, peek: false, interacting: false), "Auto hides quiet dock")
    check(!DockGeometry.hide(mode: .auto, quiet: false, hover: false, peek: false, interacting: false), "Active work stays visible in auto mode")
    check(DockGeometry.hide(mode: .hidden, quiet: false, hover: false, peek: false, interacting: false), "Explicit hidden mode also hides active work")
    check(!DockGeometry.hide(mode: .hidden, quiet: false, hover: false, peek: true, interacting: false), "Events reveal hidden dock")
    check(!DockGeometry.hide(mode: .hidden, quiet: true, hover: true, peek: false, interacting: false), "Hover reveals tab")
    check(!DockGeometry.hide(mode: .visible, quiet: true, hover: false, peek: false, interacting: false), "Always visible respects quiet")
    check(!DockGeometry.hide(mode: .auto, quiet: true, hover: false, peek: false, interacting: true), "Open list and menu hold dock open")
    check(!DockGeometry.dragging(start: .zero, point: NSPoint(x: 5.9, y: 0)), "Subthreshold movement remains a click")
    check(DockGeometry.dragging(start: .zero, point: NSPoint(x: 6, y: 0)), "Six points starts a drag")
    check(DockGeometry.dragging(start: .zero, point: NSPoint(x: 5, y: 5)), "Diagonal drag uses pointer distance")
    var config = DockConfiguration(projects: [Project(id: "one", name: "DESIGN", codexID: "codex-one", roots: ["/tmp/design"], palette: 3)])
    check((try? config.validate()) != nil, "Colleague configuration accepts custom alias and folder")
    check((try? DockConfiguration().validate()) == nil, "At least one project is required")
    let many = (0..<100).map { Project(id: String($0), name: "P" + String($0), roots: ["/tmp/p" + String($0)], palette: $0 % 4) }
    check((try? DockConfiguration(projects: many).validate()) != nil, "Project configuration has no upper limit")
    config.projects[0].name = ""
    check((try? config.validate()) == nil, "Empty aliases are rejected")
    config.projects[0].name = "123456789"
    check((try? config.validate()) == nil, "Long aliases are rejected to keep avatars readable")
    config.projects[0].name = "DESIGN"
    config.projects.append(config.projects[0])
    check((try? config.validate()) == nil, "Duplicate mappings are rejected")
    for edge in DockEdge.allCases {
        for offset in [0.0, 0.5, 1.0] {
            let dock = DockGeometry.frame(screen: screen, edge: edge, offset: offset, count: 4)
            let anchor = NSRect(x: dock.midX - 22, y: dock.midY - 22, width: 44, height: 44)
            let pop = ConversationLayout.frame(anchor: anchor, screen: screen, edge: edge, size: NSSize(width: 302, height: 520))
            check(screen.contains(pop), "Conversation list stays inside visible screen")
            check(!pop.intersects(dock), "Conversation list never covers dock")
            check(edge == .left ? pop.minX > anchor.maxX : edge == .right ? pop.maxX < anchor.minX : edge == .top ? pop.maxY < anchor.minY : pop.minY > anchor.maxY, "Popover follows inner side of selected avatar")
        }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let initial = DockConfiguration(projects: [Project(id: "one", name: "ONE", codexID: "codex-a", roots: ["/tmp/a"], palette: 0)])
    try! JSONEncoder().encode(initial).write(to: directory.appendingPathComponent("configuration.json"))
    // The fixture reader is local and deterministic; no Codex database is queried.
    try! "print('{\"connected\":true,\"tasks\":[],\"inputMonitoring\":false,\"availableProjects\":[]}')\n".write(to: directory.appendingPathComponent("backend.py"), atomically: true, encoding: .utf8)
    let model = Model(resources: directory, data: directory)
    var reply: ((Bool) -> Void)?
    var orphanPanel = false
    model.openConversation = { _, callback in reply = callback }
    let task = TaskInfo(id: "chat", project: "one", title: "Test", turn: "1", status: "completed", started: 1, completed: 2)
    model.open(task) { orphanPanel = true }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    check(reply != nil && model.openingTask != nil, "Opening is pending before configuration change")
    try! model.saveConfiguration(DockConfiguration(projects: [Project(id: "replacement", name: "NEW", roots: ["/tmp/new"], palette: 0)]))
    check(model.openingTask == nil && model.openingError == nil, "Configuration clears pending opening feedback")
    reply?(false)
    check(!orphanPanel, "Late failure cannot reopen a removed project's panel")
    model.availableProjects = [CodexProject(id: "old-project", name: "Old", roots: ["/tmp/old"])]
    var anotherHome = model.configuration
    anotherHome.codexHome = directory.appendingPathComponent("another-codex-home").path
    try! model.saveConfiguration(anotherHome)
    check(model.availableProjects.isEmpty, "Changing Codex home invalidates the previous catalog immediately")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(model.availableProjects.isEmpty, "In-flight old catalog cannot return after source change")
    print("\(checks) dock geometry, visibility, drag and configuration checks passed")
}
