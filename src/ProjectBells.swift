import AppKit
import SwiftUI

struct TaskInfo: Codable, Identifiable, Equatable {
    let id: String
    let project: String
    let title: String
    let turn: String
    let status: String
    let started: Double
    let completed: Double
    var stateChanged: Double? = nil
    var activityTime: Double { stateChanged ?? (completed > 0 ? completed : started) }
    var terminal: Bool { status == "completed" || status == "failed" }
    var eventID: String { id + ":" + turn }
    var dismissible: Bool { ["completed", "failed", "interrupted", "notLoaded"].contains(status) }
    var stateLabel: String {
        switch status {
        case "inProgress": return "En cours"
        case "waiting": return "Réponse requise"
        case "completed": return "Terminé"
        case "failed": return "En erreur"
        case "interrupted": return "Interrompu"
        default: return "Inactif"
        }
    }
    var symbol: String {
        switch status {
        case "waiting": return "questionmark.circle"
        case "completed": return "checkmark.circle"
        case "failed": return "exclamationmark.circle"
        default: return "pause.circle"
        }
    }
}
struct Snapshot: Codable, Equatable {
    let connected: Bool
    let tasks: [TaskInfo]
    let inputMonitoring: Bool
    let error: String?
    var archivedIDs: [String]? = nil
    var availableProjects: [CodexProject]? = nil
}
struct SavedState: Codable {
    var seen: [String: String] = [:]
    var notices: [TaskInfo] = []
    var dismissed: [String]?
    var retained: [TaskInfo]?
    var acknowledged: [String]?
    var sound = false
    var x: Double?
    var y: Double?
    var barWidth: Double?
    var vertical: Bool?
    var edge: DockEdge?
    var offset: Double?
    var mode: DockMode?
    var screenID: String?
}

final class Model: ObservableObject {
    @Published var tasks: [TaskInfo] = []
    @Published var connected = true
    @Published var inputMonitoring = false
    @Published var error: String?
    @Published var saved = SavedState()
    @Published var pulse = Set<String>()
    @Published var pulseStarted: [String: Date] = [:]
    @Published var selected: String?
    var didOpenTask: (() -> Void)?
    var didReceiveEvents: (([String]) -> Void)?
    var didChangeConfiguration: (() -> Void)?
    var didFallbackOpen: ((String, String) -> Void)?
    @Published var configuration = DockConfiguration()
    @Published var availableProjects: [CodexProject] = []
    var projects: [Project] { configuration.projects }
    private var configurationRevision = 0
    @Published var openingTask: String?
    @Published var openingError: String?
    var openConversation: (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { application, error in
            DispatchQueue.main.async { completion(application != nil && error == nil) }
        }
    }
    let resources: URL
    let data: URL
    private var timer: Timer?
    private var openingRequest: UUID?
    private var loading = false
    private var firstReadFailure: Date?
    private var lastCachedSnapshot: Snapshot?
    private var initialized = false
    private var lastWaiting = Set<String>()
    init(resources: URL, data: URL) {
        self.resources = resources
        self.data = data
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        if let bytes = try? Data(contentsOf: data.appendingPathComponent("state.json")),
           let state = try? JSONDecoder().decode(SavedState.self, from: bytes) { saved = state }
        if saved.acknowledged == nil {
            // Earlier releases stored read status by absence from notices. Preserve it.
            saved.acknowledged = saved.seen.compactMap { id, signature in
                let parts = signature.split(separator: ":")
                guard parts.count == 2, ["completed", "failed"].contains(String(parts[1])) else { return nil }
                let event = id + ":" + parts[0]
                return saved.notices.contains(where: { $0.eventID == event }) ? nil : event
            }
        }
        let configURL = data.appendingPathComponent("configuration.json")
        if let bytes = try? Data(contentsOf: configURL), let config = try? JSONDecoder().decode(DockConfiguration.self, from: bytes) {
            configuration = config
        } else if FileManager.default.fileExists(atPath: data.appendingPathComponent("state.json").path) {
            configuration.projects = Project.migrateLegacy(home: configuration.homeURL)
            if let bytes = try? JSONEncoder().encode(configuration) { try? bytes.write(to: configURL, options: .atomic) }
        }
        if let bytes = try? Data(contentsOf: data.appendingPathComponent("last-snapshot.json")),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: bytes), snapshot.connected {
            // Restore display only; fresh metadata alone drives new notifications.
            tasks = snapshot.tasks.filter { task in configuration.projects.contains { $0.id == task.project } }
            inputMonitoring = snapshot.inputMonitoring
            lastCachedSnapshot = snapshot
        }
    }
    func start() {
        poll()
        let refresh = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        timer = refresh
        RunLoop.main.add(refresh, forMode: .common)
    }
    func poll() {
        guard !loading else { return }
        loading = true
        let resources = self.resources, data = self.data
        let home = configuration.homeURL.path, revision = configurationRevision
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let bundled = resources.appendingPathComponent("reader")
            let standalone = FileManager.default.isExecutableFile(atPath: bundled.path)
            process.executableURL = standalone ? bundled : URL(fileURLWithPath: "/usr/bin/python3")
            process.currentDirectoryURL = data
            process.arguments = (standalone ? [] : [resources.appendingPathComponent("backend.py").path]) + ["--home", home, "--data", data.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
                defer { timeout.cancel() }
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: bytes)
                DispatchQueue.main.async {
                    self.loading = false
                    guard revision == self.configurationRevision else { self.poll(); return }
                    self.apply(snapshot)
                }
            } catch {
                DispatchQueue.main.async {
                    self.loading = false
                    guard revision == self.configurationRevision else { self.poll(); return }
                    self.recordReadFailure("Lecture Codex indisponible : \(error.localizedDescription)")
                }
            }
        }
    }
    func recordReadFailure(_ message: String, now: Date = Date()) {
        if firstReadFailure == nil { firstReadFailure = now }
        // Brief SQLite errors must not flash an alert or clear displayed tasks.
        let prolonged = now.timeIntervalSince(firstReadFailure!) >= 30
        connected = !prolonged
        error = prolonged ? message : nil
    }
    func apply(_ snapshot: Snapshot, now: Date = Date()) {
        guard snapshot.connected else {
            recordReadFailure(snapshot.error ?? "Lecture locale indisponible", now: now)
            return
        }
        firstReadFailure = nil
        connected = true
        error = nil
        if snapshot != lastCachedSnapshot,
           let bytes = try? JSONEncoder().encode(snapshot) {
            do {
                try bytes.write(to: data.appendingPathComponent("last-snapshot.json"), options: .atomic)
                lastCachedSnapshot = snapshot
            } catch { /* Optional display cache must not interrupt live tracking. */ }
        }
        inputMonitoring = snapshot.inputMonitoring
        if let catalog = snapshot.availableProjects { availableProjects = catalog }
        var changed = false
        var alerts = Set<String>()
        let archived = Set(snapshot.archivedIDs ?? [])
        let oldNotices = saved.notices
        let latestTurns = Dictionary(snapshot.tasks.map { ($0.id, $0.turn) }, uniquingKeysWith: { _, latest in latest })
        func obsolete(_ task: TaskInfo) -> Bool { archived.contains(task.id) || latestTurns[task.id].map { $0 != task.turn } == true }
        saved.notices.removeAll(where: obsolete)
        var retained = (saved.retained ?? []).filter { !obsolete($0) }
        let acknowledged = Set((saved.acknowledged ?? []) + (saved.dismissed ?? []))
        if oldNotices != saved.notices || retained != (saved.retained ?? []) { changed = true }
        for notice in saved.notices where !retained.contains(where: { $0.eventID == notice.eventID }) {
            retained.append(notice)
        }
        for task in snapshot.tasks {
            let signature = task.turn + ":" + task.status
            if initialized, saved.seen[task.id] != signature, task.status == "inProgress" { alerts.insert(task.project) }
            if let previous = saved.seen[task.id], previous != signature,
               (task.status == "completed" || task.status == "failed"),
               !acknowledged.contains(task.eventID),
               !saved.notices.contains(where: { $0.eventID == task.eventID }) {
                saved.notices.append(task)
                if !retained.contains(where: { $0.eventID == task.eventID }) { retained.append(task) }
                alerts.insert(task.project)
                changed = true
            }
            if saved.seen[task.id] != signature { saved.seen[task.id] = signature; changed = true }
        }
        if saved.retained != retained { saved.retained = retained; changed = true }
        let waiting = Set(snapshot.tasks.filter { $0.status == "waiting" }.map { $0.eventID })
        if initialized {
            for task in snapshot.tasks where waiting.subtracting(lastWaiting).contains(task.eventID) {
                alerts.insert(task.project)
            }
        }
        initialized = true
        lastWaiting = waiting
        if tasks != snapshot.tasks { tasks = snapshot.tasks }
        if changed { persist() }
        if !alerts.isEmpty {
            didReceiveEvents?(alerts.sorted())
            let started = Date()
            for project in alerts { pulseStarted[project] = started }
            pulse.formUnion(alerts)
            if saved.sound { NSSound(named: "Glass")?.play() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                for project in alerts where self.pulseStarted[project] == started {
                    self.pulse.remove(project)
                }
            }
        }
    }
    func active(_ project: String) -> [TaskInfo] {
        stable(tasks.filter { $0.project == project && $0.status == "inProgress" })
    }
    func waiting(_ project: String) -> [TaskInfo] {
        stable(tasks.filter { $0.project == project && $0.status == "waiting" })
    }
    private func stable(_ rows: [TaskInfo]) -> [TaskInfo] {
        rows.sorted { $0.started == $1.started ? $0.id < $1.id : $0.started < $1.started }
    }
    func badgeCount(_ project: String) -> Int {
        summary(project).topCount
    }
    func unread(_ project: String) -> [TaskInfo] {
        saved.notices.filter { $0.project == project }.sorted { $0.completed > $1.completed }
    }
    func visible(_ project: String) -> [TaskInfo] {
        // One row per conversation. Current synced turn wins over retained history.
        var rows: [String: TaskInfo] = [:]
        let hidden = Set(saved.dismissed ?? [])
        for task in tasks where task.project == project {
            if !hidden.contains(task.eventID) || task.status == "waiting" || task.status == "inProgress" { rows[task.id] = task }
        }
        let currentIDs = Set(tasks.filter { $0.project == project }.map { $0.id })
        for task in (saved.retained ?? []).filter({ $0.project == project }).sorted(by: { $0.activityTime > $1.activityTime }) {
            if !currentIDs.contains(task.id), rows[task.id] == nil, !hidden.contains(task.eventID) { rows[task.id] = task }
        }
        return rows.values.sorted { $0.activityTime == $1.activityTime ? $0.id < $1.id : $0.activityTime > $1.activityTime }
    }
    func priority(_ task: TaskInfo) -> Int {
        if task.status == "waiting" { return 4 }
        if task.status == "inProgress" { return 2 }
        guard saved.notices.contains(where: { $0.eventID == task.eventID }) else { return 0 }
        return task.status == "failed" ? 3 : task.status == "completed" ? 1 : 0
    }
    func conversations(_ project: String) -> [TaskInfo] {
        visible(project).filter { priority($0) > 0 }.sorted {
            let a = priority($0), b = priority($1)
            if a != b { return a > b }
            return $0.activityTime == $1.activityTime ? $0.id < $1.id : $0.activityTime < $1.activityTime
        }
    }
    func recent(_ project: String) -> [TaskInfo] {
        Array(visible(project).filter { priority($0) == 0 }.prefix(conversations(project).isEmpty ? 3 : 2))
    }
    func summary(_ project: String) -> ThreadSummary {
        let priorities = conversations(project).map { priority($0) }
        return ThreadSummary(approvals: priorities.filter { $0 == 4 }.count, failures: priorities.filter { $0 == 3 }.count,
                             running: priorities.filter { $0 == 2 }.count, done: priorities.filter { $0 == 1 }.count)
    }
    func finished(_ project: String? = nil) -> [TaskInfo] {
        let rows = project.map { visible($0) } ?? projects.flatMap { visible($0.id) }
        return rows.filter { [1, 3].contains(priority($0)) }
    }
    func dismiss(_ task: TaskInfo) {
        guard task.terminal, [1, 3].contains(priority(task)) else { return }
        markSeen(task)
    }
    func markSeen(_ task: TaskInfo) {
        guard task.terminal else { return }
        saved.notices.removeAll { $0.eventID == task.eventID }
        if !(saved.acknowledged ?? []).contains(task.eventID) { saved.acknowledged = (saved.acknowledged ?? []) + [task.eventID] }
        persist()
    }
    func markAll(_ project: String) { dismissFinished(project) }
    func dismissFinished(_ project: String? = nil) {
        let rows = finished(project)
        let ids = Set(rows.map { $0.eventID })
        saved.notices.removeAll { ids.contains($0.eventID) }
        saved.acknowledged = Array(Set((saved.acknowledged ?? []) + Array(ids))).sorted()
        persist()
    }
    func directTarget(_ project: String) -> TaskInfo? {
        let rows = conversations(project)
        let actionable = rows.filter { [1, 3, 4].contains(priority($0)) }
        if !actionable.isEmpty { return actionable.count == 1 ? actionable[0] : nil }
        let running = rows.filter { $0.status == "inProgress" }
        return running.count == 1 ? running[0] : nil
    }
    func open(_ task: TaskInfo, onFailure: (() -> Void)? = nil) {
        guard let project = projects.first(where: { $0.id == task.project }), let url = CodexLinks.thread(task.id) else { return }
        navigate(url: url, key: task.eventID, fallback: CodexLinks.newConversation(project), onFailure: onFailure) { [weak self] fallback in
            guard let self else { return }
            if fallback {
                self.didFallbackOpen?(project.id, "Le chat n’a pas pu être ouvert. Une nouvelle conversation a été ouverte dans le projet ; le résultat reste non consulté.")
            } else { self.markSeen(task) }
            self.didOpenTask?()
        }
    }
    func newConversation(_ project: Project, onFailure: (() -> Void)? = nil) {
        guard projects.contains(where: { $0.id == project.id }), let url = CodexLinks.newConversation(project) else { return }
        navigate(url: url, key: "new:" + project.id, fallback: nil, onFailure: onFailure) { [weak self] _ in self?.didOpenTask?() }
    }
    private func navigate(url: URL, key: String, fallback: URL?, onFailure: (() -> Void)?, onSuccess: @escaping (Bool) -> Void) {
        guard openingTask == nil else { return }
        let request = UUID()
        openingRequest = request; openingTask = key; openingError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.openingRequest == request else { return }
            self.openingRequest = nil; self.openingTask = nil
            self.openingError = "Codex ne confirme pas l’ouverture. Réessaie."
            onFailure?()
        }
        let finish: (Bool, Bool) -> Void = { [weak self] success, usedFallback in
            guard let self, self.openingRequest == request else { return }
            self.openingRequest = nil; self.openingTask = nil
            if success { onSuccess(usedFallback) }
            else { self.openingError = "Impossible d’ouvrir Codex. Réessaie."; onFailure?() }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.openingRequest == request else { return }
            self.openConversation(url) { [weak self] success in
                guard let self, self.openingRequest == request else { return }
                if success { finish(true, false) }
                else if let fallback { self.openConversation(fallback) { finish($0, true) } }
                else { finish(false, false) }
            }
        }
    }
    func status(_ project: String) -> DockStatus { summary(project).status }
    var quiet: Bool { projects.allSatisfy { summary($0.id).priority == 0 } }
    func saveConfiguration(_ config: DockConfiguration) throws {
        try config.validate()
        let bytes = try JSONEncoder().encode(config)
        try bytes.write(to: data.appendingPathComponent("configuration.json"), options: .atomic)
        let unchanged = Set(config.projects.filter { project in
            configuration.homeURL == config.homeURL && configuration.projects.contains { old in
                old.id == project.id && old.codexID == project.codexID && old.roots == project.roots
            }
        }.map { $0.id })
        configurationRevision += 1
        // Configuration changes invalidate both reader responses and pending launches.
        openingRequest = nil
        openingTask = nil
        openingError = nil
        if configuration.homeURL != config.homeURL { availableProjects = [] }
        configuration = config
        tasks.removeAll { !unchanged.contains($0.project) }
        saved.notices.removeAll { !unchanged.contains($0.project) }
        saved.retained = (saved.retained ?? []).filter { unchanged.contains($0.project) }
        selected = nil
        lastCachedSnapshot = nil
        try? FileManager.default.removeItem(at: data.appendingPathComponent("last-snapshot.json"))
        persist()
        didChangeConfiguration?()
        poll()
    }
    func persist() {
        if let bytes = try? JSONEncoder().encode(saved) {
            try? bytes.write(to: data.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}

struct Spinner: NSViewRepresentable {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> LoadingRingView { LoadingRingView() }
    func updateNSView(_ view: LoadingRingView, context: Context) {
        view.configure(color: NSColor(color), lineWidth: 1.6, fraction: 0.28, duration: 1.4, reduced: reduceMotion)
    }
}
