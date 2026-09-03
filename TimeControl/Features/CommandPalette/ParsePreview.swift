import SwiftUI

/// The line under the palette's field: what the current text will create, or what went wrong.
/// Keeps a fixed minimum height so the card does not jump between keystrokes.
struct ParsePreview: View {
    enum State: Equatable {
        case empty
        case unparsed
        case ready(PreviewInfo)
        case error(String)
        case success(String)
    }

    var state: State

    private static let cheatSheet = [
        "CS201 Mon/Wed 10-11:30 weeks 1-14 @Wean 5409",
        "Interview Tue 3pm · Dentist Sep 14 2pm",
        "todo Draft outline #Thesis !1 tomorrow · clear courses weeks 8-9"
    ]

    var body: some View {
        Group {
            switch state {
            case .empty:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Self.cheatSheet, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            case .unparsed:
                Text("Type more…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            case .ready(let info):
                row(info)
            case .error(let text):
                banner(text, symbol: "exclamationmark.triangle.fill", tint: .red)
            case .success(let text):
                banner(text, symbol: "checkmark.circle.fill", tint: .green)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .animation(.easeOut(duration: 0.12), value: state)
    }

    private func row(_ info: PreviewInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: info.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(info.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let footnote = info.footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

#Preview("Ready") {
    ParsePreview(state: .ready(PreviewInfo(
        symbol: "book.closed",
        title: "New course · CS201",
        detail: "Mon/Wed 10:00–11:30 · weeks 1–14 · Fall 2026",
        footnote: "Room 204"
    )))
    .padding()
    .frame(width: 560)
}

#Preview("States") {
    VStack(alignment: .leading) {
        ParsePreview(state: .empty)
        ParsePreview(state: .unparsed)
        ParsePreview(state: .error("Create a term first"))
        ParsePreview(state: .success("Added CS201 · Mon/Wed 10:00–11:30 · weeks 1–14"))
    }
    .padding()
    .frame(width: 560)
}
