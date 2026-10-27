import Foundation

struct DockPlacement: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var edge: DockEdge = .right
    var offset: Double = 0.5
    var mode: DockMode = .auto
    var screenID: String?

    func duplicate(on screens: [String], currentScreen: String) -> DockPlacement {
        var copy = self
        copy.id = UUID().uuidString
        copy.mode = .visible
        copy.screenID = screens.first { $0 != currentScreen } ?? currentScreen
        if copy.screenID == currentScreen {
            // A single physical screen can still host one dock on each side.
            copy.edge = [.left: .right, .right: .left, .top: .bottom, .bottom: .top][edge]!
        }
        return copy
    }
}
