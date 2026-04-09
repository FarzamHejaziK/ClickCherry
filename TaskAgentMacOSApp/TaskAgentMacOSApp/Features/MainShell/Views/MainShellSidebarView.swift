import AppKit
import SwiftUI

struct MainShellSidebarView: View {
    @Bindable var mainShellStateStore: MainShellStateStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                SidebarRow(
                    icon: .asset("NewTaskIcon"),
                    title: "New Task",
                    isSelected: mainShellStateStore.route == .newTask,
                    action: {
                        mainShellStateStore.openNewTask()
                    }
                )
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 12)

                    if mainShellStateStore.tasks.isEmpty {
                        Text("No tasks yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(mainShellStateStore.tasks) { task in
                                SidebarRow(
                                    icon: .system("folder"),
                                    title: task.title,
                                    isSelected: mainShellStateStore.route == .task(task.id),
                                    action: {
                                        mainShellStateStore.openTask(task.id)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        mainShellStateStore.togglePinned(taskID: task.id)
                                    } label: {
                                        if mainShellStateStore.isTaskPinned(task.id) {
                                            Label("Unpin", systemImage: "pin.slash")
                                        } else {
                                            Label("Pin to top", systemImage: "pin")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        mainShellStateStore.requestDeleteTask(taskID: task.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    Spacer(minLength: 10)
                }
            }
            .scrollIndicators(.never)

            Divider()

            SidebarRow(
                icon: .asset("SettingsIcon"),
                title: "Settings",
                isSelected: mainShellStateStore.route == .settings,
                action: {
                    mainShellStateStore.openSettings()
                }
            )
            .padding(12)
        }
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow)

                // Sidebar tint: keep it subtle so it doesn't overpower the main content column.
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .alert(
            "Delete task?",
            isPresented: $mainShellStateStore.isShowingDeleteTaskAlert
        ) {
            Button("Cancel", role: .cancel) {
                mainShellStateStore.cancelDeleteTask()
            }
            Button("Delete", role: .destructive) {
                mainShellStateStore.confirmDeleteTask()
            }
        } message: {
            Text("This will permanently delete the task workspace and its files.")
        }
    }
}

private enum SidebarIcon {
    case asset(String)
    case system(String)

    @ViewBuilder
    var image: some View {
        switch self {
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        case .system(let name):
            Image(systemName: name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        }
    }
}

private struct SidebarRow: View {
    let icon: SidebarIcon
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.image
                    .frame(width: 16, height: 16)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .onHover { hovering in
            isHovered = hovering
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}
