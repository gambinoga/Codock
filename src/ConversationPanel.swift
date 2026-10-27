import SwiftUI

struct TasksPanel: View {
    @ObservedObject var model: Model
    let project: Project
    var panelSize = NSSize(width: 302, height: 320)
    var body: some View {
        let active = model.conversations(project.id)
        let recent = model.recent(project.id)
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(project.color).frame(width: 8, height: 8)
                    Text(project.name).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                Text(model.summary(project.id).label).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
            }.padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            if !model.connected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Refresh delayed — last known state").font(.caption).foregroundColor(.secondary)
                    Button("Retry now") { model.poll() }.buttonStyle(.plain).foregroundColor(project.color)
                    DisclosureGroup("Details") { Text(model.error ?? "Local metadata is unavailable").font(.caption).foregroundColor(.secondary) }
                }.padding(.horizontal, 10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(active, id: \.eventID) { task in ConversationRow(model: model, project: project, task: task) }
                    if !recent.isEmpty {
                        Text("Recent").font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 3)
                        ForEach(recent, id: \.eventID) { task in ConversationRow(model: model, project: project, task: task) }
                    }
                    if active.isEmpty && recent.isEmpty {
                        Text(model.connected ? "No conversations yet" : "Waiting for refresh")
                            .font(.system(size: 12)).foregroundColor(.secondary).padding(10)
                    }
                }.animation(nil, value: active.map { $0.eventID }).animation(nil, value: recent.map { $0.eventID })
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.openingError {
                Text(error).font(.system(size: 11)).foregroundColor(.red).lineLimit(3).padding(.horizontal, 10)
            }
            Divider().padding(.horizontal, 6)
            Button { model.newConversation(project) } label: {
                HStack(spacing: 10) {
                    if model.openingTask == "new:" + project.id { Spinner(color: project.color).frame(width: 17, height: 17) }
                    else { Image(systemName: "plus").font(.system(size: 16)).frame(width: 17) }
                    Text(model.openingTask == "new:" + project.id ? "Opening…" : "New conversation").font(.system(size: 13))
                    Spacer()
                }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.openingTask != nil)
        }.padding(6).frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .dockSurface)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
struct ConversationRow: View {
    @ObservedObject var model: Model
    let project: Project
    let task: TaskInfo
    @State private var hovered = false
    var body: some View {
        let priority = model.priority(task)
        HStack(spacing: 0) {
            Button { model.open(task) } label: {
                HStack(spacing: 10) {
                    if priority == 2 { Spinner(color: project.color).frame(width: 17, height: 17) }
                    else { Image(systemName: priority == 4 ? "hand.raised" : priority == 3 ? "exclamationmark.triangle" : priority == 1 ? "checkmark.circle" : "clock.arrow.circlepath")
                        .font(.system(size: 16)).foregroundColor(stateColor(priority)).frame(width: 17, height: 17) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.system(size: 13)).foregroundColor(priority == 0 ? .secondary : .primary).lineLimit(1).truncationMode(.tail)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(model.openingTask == task.eventID ? "Opening…" : ConversationTime.text(task: task, now: context.date))
                                .font(.system(size: 12)).foregroundColor(priority >= 3 ? stateColor(priority) : .secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if model.openingTask == task.eventID { Spinner(color: project.color).frame(width: 13, height: 13) }
                }.padding(.leading, 10).padding(.trailing, 4).frame(maxWidth: .infinity, minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.openingTask != nil).accessibilityLabel("Open \(task.title)")
            if [1, 3].contains(priority) {
                Button { model.dismiss(task) } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 28, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Mark as read").accessibilityLabel("Dismiss \(task.title)")
            } else { Spacer().frame(width: 10) }
        }.background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovered ? 0.045 : 0)))
            .onHover { hovered = $0 }
    }
    func stateColor(_ priority: Int) -> Color {
        priority == 4 ? Color(nsColor: .hex("BA7517")) : priority == 3 ? Color(nsColor: .hex("E24B4A")) : priority == 1 ? Color(nsColor: .hex("639922")) : .secondary
    }
}
