import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The single screen: a sectioned task list, the pinned composer, the recent
/// conversation thread, and the confirmation-card host.
@MainActor
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)])
    private var tasks: [TaskItem]

    @State private var agent: AgentService
    @State private var composerText: String = ""

    /// Production initializer — wires the real `URLSession`-backed client.
    init() {
        let configuration = AppConfig.configuration
        _agent = State(initialValue: AgentService(
            client: URLSessionAnthropicClient(configuration: configuration),
            configuration: configuration))
    }

    /// Injection initializer for previews/tests.
    init(agent: AgentService) {
        _agent = State(initialValue: agent)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cue")
                .navigationBarTitleDisplayMode(.large)
                .background(Color(.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimationIfAllowed { agent.clearConversation() }
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .disabled(agent.messages.isEmpty && agent.pendingAction == nil)
                        .accessibilityLabel("Clear conversation")
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .task { agent.modelContext = modelContext }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if tasks.isEmpty {
            EmptyStateView()
        } else {
            taskList
        }
    }

    private var taskList: some View {
        List {
            section("Today", tasks: todayTasks)
            section("Upcoming", tasks: upcomingTasks)
            section("No date", tasks: noDateTasks)
            section("Completed", tasks: completedTasks)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : .snappy, value: taskSignature)
    }

    @ViewBuilder
    private func section(_ title: String, tasks list: [TaskItem]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { task in
                    TaskRowView(task: task) { toggle(task) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete(task) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { toggle(task) } label: {
                                Label(task.isComplete ? "Reopen" : "Complete",
                                      systemImage: task.isComplete ? "arrow.uturn.left" : "checkmark")
                            }
                            .tint(.cueAccent)
                        }
                }
            }
        }
    }

    // MARK: - Bottom bar (thread + card + composer)

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if !agent.isConfigured {
                setupBanner
            }
            ForEach(recentMessages) { message in
                AssistantBubbleView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if agent.isThinking {
                ThinkingIndicator()
                    .transition(.opacity)
            }
            if let action = agent.pendingAction {
                ConfirmationCardView(
                    action: action,
                    onConfirm: { confirm(action) },
                    onCancel: { cancel(action) },
                    onEdit: { edit(action) })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ComposerView(text: $composerText,
                         isSending: agent.isThinking || agent.pendingAction != nil,
                         onSend: submit)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, Theme.Spacing.s)
        .animation(reduceMotion ? nil : .snappy, value: agent.pendingAction)
        .animation(reduceMotion ? nil : .easeInOut, value: agent.isThinking)
        .animation(reduceMotion ? nil : .snappy, value: recentMessages.map(\.id))
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "key.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Add your Anthropic API key in Config/Secrets.xcconfig to enable Cue. See the README.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.regularMaterial))
    }

    private var recentMessages: [ChatMessage] {
        Array(agent.messages.suffix(3))
    }

    // MARK: - Actions

    private func submit() {
        let text = composerText
        composerText = ""
        // Dismiss the keyboard so the thinking indicator and confirmation card are
        // fully visible (otherwise the card the user must confirm sits behind it).
        dismissKeyboard()
        Task { await agent.submit(text) }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func confirm(_ action: PendingAction) {
        Task { await agent.confirm(action) }
    }

    private func cancel(_ action: PendingAction) {
        Task { await agent.cancel(action) }
    }

    private func edit(_ action: PendingAction) {
        composerText = action.summary
        Haptics.selection()
        Task { await agent.cancel(action) }
    }

    private func toggle(_ task: TaskItem) {
        Haptics.light()
        withAnimationIfAllowed {
            task.isComplete.toggle()
            try? modelContext.save()
        }
    }

    private func delete(_ task: TaskItem) {
        Haptics.light()
        withAnimationIfAllowed {
            modelContext.delete(task)
            try? modelContext.save()
        }
    }

    private func withAnimationIfAllowed(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.snappy, body)
        }
    }

    // MARK: - Task grouping

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isComplete } }

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        return activeTasks
            .filter { if let date = $0.datetime { return calendar.isDateInToday(date) }; return false }
            .sorted(by: earlierDate)
    }

    private var upcomingTasks: [TaskItem] {
        let calendar = Calendar.current
        return activeTasks
            .filter {
                guard let date = $0.datetime else { return false }
                return !calendar.isDateInToday(date)
            }
            .sorted(by: earlierDate)
    }

    private var noDateTasks: [TaskItem] {
        activeTasks.filter { $0.datetime == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    private var completedTasks: [TaskItem] {
        tasks.filter { $0.isComplete }
            .sorted { ($0.datetime ?? .distantPast) > ($1.datetime ?? .distantPast) }
    }

    private func earlierDate(_ a: TaskItem, _ b: TaskItem) -> Bool {
        (a.datetime ?? .distantFuture) < (b.datetime ?? .distantFuture)
    }

    /// Drives list animation: changes on insert/delete and on completion toggle.
    private var taskSignature: String {
        tasks.map { "\($0.id.uuidString):\($0.isComplete)" }.joined(separator: "|")
    }
}

#if DEBUG
#Preview("Empty") {
    HomeView(agent: .previewService())
        .modelContainer(PreviewData.emptyContainer)
}

#Preview("Populated") {
    HomeView(agent: .previewService())
        .modelContainer(PreviewData.container)
}

#Preview("Confirmation visible") {
    let agent = AgentService.previewService()
    agent.previewSeed(
        messages: [.user("schedule a call with Marko next Tuesday at 3pm")],
        pendingAction: PendingAction(
            id: "1", toolName: "create_task", verb: .add,
            summary: "Call with Marko", title: "Call with Marko",
            datetime: Date().addingTimeInterval(3 * 3600),
            datetimeWasDefaulted: false, notes: nil, rawInput: .object([:])))
    return HomeView(agent: agent).modelContainer(PreviewData.container)
}

#Preview("Thinking") {
    let agent = AgentService.previewService()
    agent.previewSeed(messages: [.user("add buy groceries")], isThinking: true)
    return HomeView(agent: agent).modelContainer(PreviewData.container)
}

#Preview("Error / offline") {
    let agent = AgentService.previewService()
    agent.previewSeed(messages: [
        .user("move my meeting"),
        ChatMessage(role: .assistant,
                    text: "I couldn't reach the model — check your connection and try again.",
                    isError: true)
    ])
    return HomeView(agent: agent).modelContainer(PreviewData.container)
}
#endif
