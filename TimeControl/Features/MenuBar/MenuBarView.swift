#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import TimeControlCore

/// Content of the `MenuBarExtra` window: today's ring, the next thing on the schedule, and a quick todo list.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @Query private var seriesList: [Series]
    @Query private var events: [Event]
    @Query private var blackouts: [Blackout]
    @Query private var exceptions: [OccurrenceException]
    @Query private var todos: [TodoItem]

    @State private var newTodoTitle = ""

    private var today: DayKey { .today() }

    private var snapshot: ScheduleSnapshot {
        ScheduleSnapshot(series: seriesList, events: events, blackouts: blackouts, exceptions: exceptions)
    }

    private var dailyProgress: RingProgress { RingMath.daily(todos.map(\.spec), on: today) }

    private var openTodayTodos: [TodoItem] {
        todos.filter { $0.day == today && !$0.isDone }.sorted(by: TodoItem.listOrder)
    }

    private var visibleTodayTodos: [TodoItem] { Array(openTodayTodos.prefix(6)) }
    private var remainingTodayCount: Int { max(0, openTodayTodos.count - 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            Divider()
            nextUpSection
            Divider()
            todosSection
            Divider()
            footerSection
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            RingView(progress: dailyProgress, lineWidth: 7, label: .fraction)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.headline)
                Text(dailyProgress.isEmpty ? "Nothing planned" : "\(dailyProgress.done) of \(dailyProgress.total) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(today.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Next up

    private var nextUpSection: some View {
        TimelineView(.everyMinute) { context in
            if let occurrence = snapshot.next(after: context.date) {
                nextUpRow(for: occurrence, now: context.date)
            } else {
                Text("No more events soon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nextUpRow(for occurrence: Occurrence, now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color(hex: occurrence.colorHex))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                nextUpDetail(for: occurrence, now: now)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !occurrence.location.isEmpty {
                    Text(occurrence.location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func nextUpDetail(for occurrence: Occurrence, now: Date) -> Text {
        if now < occurrence.start {
            Text(occurrence.start, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            + Text(" · ")
            + Text(occurrence.start...occurrence.end)
        } else {
            Text("now · until ") + Text(occurrence.end, format: .dateTime.hour().minute())
        }
    }

    // MARK: Todos

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleTodayTodos.isEmpty {
                Text("Nothing planned for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleTodayTodos) { todo in
                        TodoRow(todo: todo, showsProject: true)
                    }
                }
            }
            if remainingTodayCount > 0 {
                Button {
                    openTodosInApp()
                } label: {
                    Text("+ \(remainingTodayCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            TextField("Add a todo for today", text: $newTodoTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTodo)
        }
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(TodoItem(title: trimmed, day: today))
        newTodoTitle = ""
    }

    private func openTodosInApp() {
        appState.section = .todos
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    // MARK: Footer

    private var footerSection: some View {
        HStack {
            Button("Open TimeControl") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
#endif
