import AppKit
import SwiftUI

struct ProjectSettings: View {
    @ObservedObject var model: Model
    let shortcutAvailable: Bool
    @State private var draft: DockConfiguration
    @State private var message: String?
    @State private var failure = false
    init(model: Model, shortcutAvailable: Bool) {
        self.model = model; self.shortcutAvailable = shortcutAvailable
        _draft = State(initialValue: model.configuration)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your dock, your projects").font(.system(size: 22, weight: .semibold))
                    Text("\(draft.projects.count) project\(draft.projects.count == 1 ? "" : "s") · Add as many projects as you like.").foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack {
                Text("Codex data").fontWeight(.medium)
                Text(draft.homeURL.path).lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                Spacer()
                Button("Choose…") { chooseCodexHome() }
            }
            HStack(spacing: 12) {
                ColorPicker("Dock background", selection: Binding(
                    get: { Color(nsColor: draft.barColor) },
                    set: { draft.barBackground = NSColor($0).rgbHex }
                ), supportsOpacity: false).fixedSize()
                if draft.barBackground != nil {
                    Button("Automatic") { draft.barBackground = nil }.buttonStyle(.link)
                }
                Spacer()
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(draft.projects.enumerated()), id: \.element.id) { index, project in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color(nsColor: .hex(project.colors[0]))).frame(width: 44, height: 44)
                                    Text(project.name).font(.system(size: 11, weight: .medium)).foregroundColor(Color(nsColor: .hex(project.colors[1])))
                                }
                                TextField("Alias", text: $draft.projects[index].name).frame(width: 88)
                                    .accessibilityLabel("Project alias \(index + 1)")
                                Picker("Color", selection: Binding(
                                    get: { draft.projects[index].customAccent == nil ? draft.projects[index].palette : -1 },
                                    set: { choice in
                                        if choice == -1 { draft.projects[index].customAccent = draft.projects[index].colors[2] }
                                        else { draft.projects[index].palette = choice; draft.projects[index].customAccent = nil }
                                    })) {
                                    ForEach(Project.paletteNames.indices, id: \.self) { option in Text(Project.paletteNames[option]).tag(option) }
                                    Text("Custom").tag(-1)
                                }.labelsHidden().frame(width: 110)
                                ColorPicker("Custom accent for \(project.name)", selection: Binding(
                                    get: { Color(nsColor: .hex(draft.projects[index].colors[2])) },
                                    set: { draft.projects[index].customAccent = NSColor($0).rgbHex }
                                ), supportsOpacity: false).labelsHidden().frame(width: 28)
                                    .help("Choose a custom color")
                                Spacer()
                                Button { if index > 0 { draft.projects.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move project up")
                                Button { draft.projects.removeAll { $0.id == project.id } } label: { Image(systemName: "minus.circle") }.disabled(draft.projects.count == 1).help("Remove from dock")
                            }
                            HStack(spacing: 10) {
                                ColorPicker("Background", selection: Binding(
                                    get: { Color(nsColor: .hex(draft.projects[index].colors[0])) },
                                    set: { draft.projects[index].customBackground = NSColor($0).rgbHex }
                                ), supportsOpacity: false).fixedSize()
                                    .accessibilityLabel("Avatar background for \(project.name)")
                                if project.customBackground != nil {
                                    Button("Automatic background") { draft.projects[index].customBackground = nil }
                                        .buttonStyle(.link).font(.caption)
                                }
                                Spacer()
                            }
                            HStack {
                                Text(project.roots.joined(separator: ", ")).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                Spacer()
                            }
                        }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    }
                    if draft.projects.isEmpty { Text("Add a Codex project or choose a folder.").foregroundColor(.secondary).padding(.vertical, 40) }
                }
            }
            HStack {
                Menu("Add a Codex project") {
                    ForEach(model.availableProjects) { project in
                        Button(project.name) { add(project) }.disabled(draft.projects.contains { $0.codexID == project.id })
                    }
                    if model.availableProjects.isEmpty { Text("No projects detected") }
                }.disabled(draft.homeURL != model.configuration.homeURL)
                Button("Choose a folder…") { addFolder() }
                Spacer()
            }
            Divider()
            HStack {
                Text(shortcutAvailable ? "⌥⌘J: show / hide" : "⌥⌘J is already used by another application.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Help and input detection") {
                    NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("USER_GUIDE.txt"))
                }
            }
            HStack {
                if let message { Text(message).font(.caption).foregroundColor(failure ? .red : .secondary).lineLimit(2) }
                Spacer()
                Button("Revert changes") { draft = model.configuration; message = nil }
                Button("Save") {
                    do { try model.saveConfiguration(draft); failure = false; message = "Settings saved." }
                    catch { failure = true; message = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(draft.projects.isEmpty)
            }
        }.padding(24).frame(width: 600, height: 560)
    }
    func panel(title: String) -> NSOpenPanel {
        let picker = NSOpenPanel(); picker.title = title; picker.canChooseDirectories = true
        picker.canChooseFiles = false; picker.allowsMultipleSelection = false; picker.showsHiddenFiles = true
        return picker
    }
    func chooseCodexHome() {
        let picker = panel(title: "Choose the Codex data folder (.codex)")
        picker.directoryURL = draft.homeURL
        if picker.runModal() == .OK, let url = picker.url {
            if url.standardizedFileURL != draft.homeURL.standardizedFileURL { draft.projects = [] }
            draft.codexHome = url.path
            message = "Add a project folder if needed, then save to detect projects in this Codex data folder."
            failure = false
        }
    }
    func add(_ item: CodexProject) {
        guard !draft.projects.contains(where: { $0.codexID == item.id }) else { return }
        draft.projects.append(Project(id: UUID().uuidString, name: String(item.name.prefix(8)).uppercased(), codexID: item.id, roots: item.roots, palette: draft.projects.count % Project.palettes.count))
        message = nil
    }
    func addFolder() {
        let picker = panel(title: "Choose the project folder to monitor")
        if picker.runModal() == .OK, let url = picker.url {
            let known = draft.homeURL == model.configuration.homeURL ? model.availableProjects.first { project in project.roots.contains { URL(fileURLWithPath: $0).standardizedFileURL == url.standardizedFileURL } } : nil
            if let known { add(known); return }
            guard !draft.projects.contains(where: { $0.roots.contains(url.path) }) else { failure = true; message = "This folder is already in the dock."; return }
            draft.projects.append(Project(id: UUID().uuidString, name: String(url.lastPathComponent.prefix(8)).uppercased(), codexID: nil, roots: [url.path], palette: draft.projects.count % Project.palettes.count))
            message = "This folder and its subfolders will be monitored. You can edit the alias."
            failure = false
        }
    }
}
