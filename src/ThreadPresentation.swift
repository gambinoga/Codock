import Foundation
import AppKit

struct ThreadSummary: Equatable {
    let approvals: Int
    let failures: Int
    let running: Int
    let done: Int
    var priority: Int { approvals > 0 ? 4 : failures > 0 ? 3 : running > 0 ? 2 : done > 0 ? 1 : 0 }
    var topCount: Int { [0, done, running, failures, approvals][priority] }
    var status: DockStatus { [.idle, .done, .running, .failed, .approval][priority] }
    var badgeText: String? {
        if topCount > 1 { return topCount > 99 ? "99+" : String(topCount) }
        return priority == 4 ? "!" : priority == 3 ? "×" : nil
    }
    var hasBadge: Bool { priority == 1 || priority == 3 || priority == 4 || (priority == 2 && running > 1) }
    var label: String {
        var parts: [String] = []
        if approvals > 0 { parts.append("\(approvals) need\(approvals == 1 ? "s" : "") input") }
        if failures > 0 { parts.append("\(failures) failed") }
        if running > 0 { parts.append("\(running) running") }
        if done > 0 { parts.append("\(done) done") }
        return parts.isEmpty ? "Nothing running" : parts.joined(separator: " · ")
    }
}
struct ConversationLayout {
    static func frame(anchor: NSRect, screen: NSRect, edge: DockEdge, size: NSSize, gap: CGFloat = 18) -> NSRect {
        var size = NSSize(width: min(size.width, screen.width - 12), height: min(size.height, screen.height - 12))
        // Keep the popover on the inner side even on short displays.
        if edge == .top { size.height = min(size.height, max(1, anchor.minY - screen.minY - gap - 6)) }
        if edge == .bottom { size.height = min(size.height, max(1, screen.maxY - anchor.maxY - gap - 6)) }
        if edge == .left { size.width = min(size.width, max(1, screen.maxX - anchor.maxX - gap - 6)) }
        if edge == .right { size.width = min(size.width, max(1, anchor.minX - screen.minX - gap - 6)) }
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        switch edge {
        case .left: origin.x = anchor.maxX + gap
        case .right: origin.x = anchor.minX - gap - size.width
        case .top: origin.y = anchor.minY - gap - size.height
        case .bottom: origin.y = anchor.maxY + gap
        }
        origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - size.width - 6)
        origin.y = min(max(origin.y, screen.minY + 6), screen.maxY - size.height - 6)
        return NSRect(origin: origin, size: size)
    }
    static func size(active: Int, recent: Int, hasError: Bool) -> NSSize {
        NSSize(width: 302, height: min(520, max(140, 108 + CGFloat(active + recent) * 54 + (recent > 0 ? 22 : 0) + (hasError ? 42 : 0))))
    }
}
struct ConversationTime {
    static func text(task: TaskInfo, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince1970 - task.activityTime)
        if task.status == "inProgress" {
            let seconds = Int(elapsed)
            return "Running · \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        let minutes = Int(elapsed / 60)
        let ago = minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : minutes < 1440 ? "\(minutes / 60) h ago" : "\(minutes / 1440) d ago"
        return task.stateLabel + " · " + ago
    }
}
struct CodexLinks {
    static func thread(_ id: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "codex"; parts.host = "threads"; parts.path = "/" + id
        return parts.url
    }
    // Official documented link opens a new composer in the project's workspace.
    // It never sends a prompt or starts an agent without the user's input.
    static func newConversation(_ project: Project) -> URL? {
        guard let root = project.roots.first, root.hasPrefix("/") else { return nil }
        var parts = URLComponents()
        parts.scheme = "codex"; parts.host = "threads"; parts.path = "/new"
        parts.queryItems = [URLQueryItem(name: "path", value: root)]
        return parts.url
    }
}
