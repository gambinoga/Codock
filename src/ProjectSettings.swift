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
                    Text("Ton dock, tes projets").font(.system(size: 22, weight: .semibold))
                    Text("\(draft.projects.count) projet\(draft.projects.count == 1 ? "" : "s") · Ajoute autant de projets que tu veux.").foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack {
                Text("Données Codex").fontWeight(.medium)
                Text(draft.homeURL.path).lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                Spacer()
                Button("Choisir…") { chooseCodexHome() }
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
                                    .accessibilityLabel("Alias du projet \(index + 1)")
                                Picker("Couleur", selection: $draft.projects[index].palette) {
                                    Text("Bleu").tag(0); Text("Terre cuite").tag(1); Text("Menthe").tag(2); Text("Lavande").tag(3)
                                }.labelsHidden().frame(width: 110)
                                Spacer()
                                Button { if index > 0 { draft.projects.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Monter le projet")
                                Button { draft.projects.removeAll { $0.id == project.id } } label: { Image(systemName: "minus.circle") }.disabled(draft.projects.count == 1).help("Retirer du dock")
                            }
                            HStack {
                                Text(project.roots.joined(separator: ", ")).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                Spacer()
                            }
                        }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    }
                    if draft.projects.isEmpty { Text("Ajoute un projet Codex ou choisis un dossier.").foregroundColor(.secondary).padding(.vertical, 40) }
                }
            }
            HStack {
                Menu("Ajouter un projet Codex") {
                    ForEach(model.availableProjects) { project in
                        Button(project.name) { add(project) }.disabled(draft.projects.contains { $0.codexID == project.id })
                    }
                    if model.availableProjects.isEmpty { Text("Aucun projet détecté") }
                }.disabled(draft.homeURL != model.configuration.homeURL)
                Button("Choisir un dossier…") { addFolder() }
                Spacer()
            }
            Divider()
            HStack {
                Text(shortcutAvailable ? "⌥⌘J : afficher / masquer" : "⌥⌘J est déjà utilisé par une autre application.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Guide et détection des demandes") {
                    NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("LIRE-MOI.txt"))
                }
            }
            HStack {
                if let message { Text(message).font(.caption).foregroundColor(failure ? .red : .secondary).lineLimit(2) }
                Spacer()
                Button("Annuler les modifications") { draft = model.configuration; message = nil }
                Button("Enregistrer") {
                    do { try model.saveConfiguration(draft); failure = false; message = "Réglages enregistrés." }
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
        let picker = panel(title: "Choisir le dossier de données Codex (.codex)")
        picker.directoryURL = draft.homeURL
        if picker.runModal() == .OK, let url = picker.url {
            if url.standardizedFileURL != draft.homeURL.standardizedFileURL { draft.projects = [] }
            draft.codexHome = url.path
            message = "Enregistre pour détecter les projets de ce dossier Codex."
            failure = false
        }
    }
    func add(_ item: CodexProject) {
        guard !draft.projects.contains(where: { $0.codexID == item.id }) else { return }
        draft.projects.append(Project(id: UUID().uuidString, name: String(item.name.prefix(8)).uppercased(), codexID: item.id, roots: item.roots, palette: draft.projects.count % Project.palettes.count))
        message = nil
    }
    func addFolder() {
        let picker = panel(title: "Choisir le dossier du projet à suivre")
        if picker.runModal() == .OK, let url = picker.url {
            let known = draft.homeURL == model.configuration.homeURL ? model.availableProjects.first { project in project.roots.contains { URL(fileURLWithPath: $0).standardizedFileURL == url.standardizedFileURL } } : nil
            if let known { add(known); return }
            guard !draft.projects.contains(where: { $0.roots.contains(url.path) }) else { failure = true; message = "Ce dossier est déjà dans le dock."; return }
            draft.projects.append(Project(id: UUID().uuidString, name: String(url.lastPathComponent.prefix(8)).uppercased(), codexID: nil, roots: [url.path], palette: draft.projects.count % Project.palettes.count))
            message = "Le suivi utilisera ce dossier et ses sous-dossiers. Tu peux modifier l’alias."
            failure = false
        }
    }
}
