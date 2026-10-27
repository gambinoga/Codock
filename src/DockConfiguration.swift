import AppKit
import SwiftUI

struct CodexProject: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let roots: [String]
}
struct Project: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var codexID: String?
    var roots: [String]
    var palette: Int
    var customAccent: String? = nil
    var customBackground: String? = nil
    static let palettes = [
        ["E6F1FB", "0C447C", "378ADD"], ["FAECE7", "712B13", "D85A30"],
        ["E1F5EE", "085041", "1D9E75"], ["EEEDFE", "3C3489", "7F77DD"],
        ["E0F4FA", "07566B", "0891B2"], ["E8EDFF", "283B80", "4F64D8"],
        ["FCE7F0", "831843", "DB2777"], ["FAE8FF", "701A75", "C026D3"],
        ["FFF0DB", "783B10", "D97706"], ["F5F3CF", "575312", "9A8F20"],
        ["E9EDF1", "334155", "64748B"], ["E0F5F2", "134E4A", "0D9488"]
    ]
    static let paletteNames = ["Blue", "Terracotta", "Mint", "Lavender", "Cyan", "Indigo", "Pink", "Fuchsia", "Orange", "Olive", "Slate", "Turquoise"]
    var colors: [String] {
        var result = Self.palettes[max(0, min(Self.palettes.count - 1, palette))]
        if let customAccent {
            let accent = NSColor.hex(customAccent)
            result = [(accent.blended(withFraction: 0.88, of: .white) ?? accent).rgbHex,
                      (accent.blended(withFraction: 0.72, of: .black) ?? accent).rgbHex, accent.rgbHex]
        }
        if let customBackground {
            result[0] = customBackground
            let background = NSColor.hex(customBackground)
            // Keep the palette's text when readable; otherwise use black or white.
            if background.contrastRatio(with: .hex(result[1])) < 4.5 {
                result[1] = background.contrastRatio(with: .black) >= background.contrastRatio(with: .white) ? "000000" : "FFFFFF"
            }
        }
        return result
    }
    var color: Color { Color(nsColor: NSColor.hex(colors[2])) }
    static func migrateLegacy(home: URL) -> [Project] {
        guard let bytes = try? Data(contentsOf: home.appendingPathComponent(".codex-global-state.json")),
              let state = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let catalog = state["local-projects"] as? [String: [String: Any]] else { return [] }
        return ["dss14", "dss14-b", "dss14-c", "dss14-d"].enumerated().compactMap { index, name in
            guard let entry = catalog.first(where: { $0.value["name"] as? String == name }),
                  let roots = entry.value["rootPaths"] as? [String], !roots.isEmpty else { return nil }
            return Project(id: name, name: index == 0 ? "DSS" : "DSS-" + String(UnicodeScalar(65 + index)!), codexID: entry.key, roots: roots, palette: index)
        }
    }
}
struct DockConfiguration: Codable, Equatable {
    var projects: [Project] = []
    var codexHome: String? = nil
    var barBackground: String? = nil
    var barColor: NSColor { barBackground.map { .hex($0) } ?? .dockSurface }
    var homeURL: URL {
        if let home = codexHome, !home.isEmpty { return URL(fileURLWithPath: (home as NSString).expandingTildeInPath) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    func validate() throws {
        func invalid(_ message: String) -> NSError { NSError(domain: "Codock", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        if let value = barBackground {
            guard value.count == 6, value.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { throw invalid("The dock background must be a valid RGB hex color.") }
        }
        guard !projects.isEmpty else { throw invalid("Choose at least one project.") }
        guard Set(projects.map { $0.id }).count == projects.count else { throw invalid("A project can only appear once.") }
        guard Set(projects.compactMap { $0.codexID }).count == projects.compactMap({ $0.codexID }).count else { throw invalid("This Codex project is already selected.") }
        for project in projects {
            for value in [project.customAccent, project.customBackground].compactMap({ $0 }) {
                guard value.count == 6, value.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { throw invalid("Colors must be valid RGB hex codes.") }
            }
            guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, project.name.count <= 8 else { throw invalid("Each alias must contain 1–8 characters.") }
            guard !project.roots.isEmpty, project.roots.allSatisfy({ $0.hasPrefix("/") }) else { throw invalid("Choose a folder for each project.") }
        }
    }
}
extension NSColor {
    var relativeLuminance: CGFloat {
        let rgb = usingColorSpace(.sRGB) ?? .black
        func linear(_ value: CGFloat) -> CGFloat {
            let value = min(1, max(0, value))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    func contrastRatio(with other: NSColor) -> CGFloat {
        let first = relativeLuminance, second = other.relativeLuminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
    var rgbHex: String {
        let rgb = usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int(min(255, max(0, (rgb.redComponent * 255).rounded()))), Int(min(255, max(0, (rgb.greenComponent * 255).rounded()))), Int(min(255, max(0, (rgb.blueComponent * 255).rounded()))))
    }
    static func hex(_ value: String) -> NSColor {
        let value = UInt32(value.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static var dockSurface: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .hex("2C2C2A") : .white
        }
    }
}
enum DockEdge: String, Codable, CaseIterable {
    case left, right, top, bottom
    var vertical: Bool { self == .left || self == .right }
}
enum DockMode: String, Codable { case visible, auto, hidden }
enum DockStatus: String {
    case idle, running, approval, failed, done
    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .approval: return "Needs input — click to open"
        case .failed: return "Failed"
        case .done: return "Done — click to read"
        }
    }
}
struct DockGeometry {
    static func size(count: Int, edge: DockEdge) -> NSSize {
        let length = CGFloat(max(1, count)) * 44 + CGFloat(max(0, count - 1)) * 14 + 24
        return edge.vertical ? NSSize(width: 64, height: length) : NSSize(width: length, height: 64)
    }
    static func frame(screen: NSRect, edge: DockEdge, offset: Double, count: Int, tab: Bool = false) -> NSRect {
        var size = tab ? (edge.vertical ? NSSize(width: 10, height: 64) : NSSize(width: 64, height: 10)) : size(count: count, edge: edge)
        if !tab {
            if edge.vertical { size.height = min(size.height, max(64, screen.height - 24)) }
            else { size.width = min(size.width, max(64, screen.width - 24)) }
        }
        let margin: CGFloat = tab ? 0 : 12
        let off = CGFloat(offset.isFinite ? min(1, max(0, offset)) : 0.5)
        let x = edge == .left ? screen.minX + margin : edge == .right ? screen.maxX - size.width - margin
            : min(max(screen.minX + off * screen.width - size.width / 2, screen.minX + 12), screen.maxX - size.width - 12)
        let y = edge == .bottom ? screen.minY + margin : edge == .top ? screen.maxY - size.height - margin
            : min(max(screen.minY + off * screen.height - size.height / 2, screen.minY + 12), screen.maxY - size.height - 12)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
    static func dragging(start: NSPoint, point: NSPoint) -> Bool { hypot(point.x - start.x, point.y - start.y) >= 6 }
    static func nearest(_ point: NSPoint, screen: NSRect) -> DockEdge {
        let distances: [(DockEdge, CGFloat)] = [(.left, abs(point.x - screen.minX)), (.right, abs(screen.maxX - point.x)), (.top, abs(screen.maxY - point.y)), (.bottom, abs(point.y - screen.minY))]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }
    static func offset(frame: NSRect, screen: NSRect, edge: DockEdge) -> Double {
        let value = edge.vertical ? (frame.midY - screen.minY) / screen.height : (frame.midX - screen.minX) / screen.width
        return Double(min(1, max(0, value)))
    }
    static func offscreen(_ frame: NSRect, edge: DockEdge) -> NSRect {
        var rect = frame
        switch edge {
        case .left: rect.origin.x -= frame.width + 30
        case .right: rect.origin.x += frame.width + 30
        case .top: rect.origin.y += frame.height + 30
        case .bottom: rect.origin.y -= frame.height + 30
        }
        return rect
    }
    static func hide(mode: DockMode, quiet: Bool, hover: Bool, peek: Bool, interacting: Bool) -> Bool {
        if hover || peek || interacting { return false }
        return mode == .hidden || (mode == .auto && quiet)
    }
}
