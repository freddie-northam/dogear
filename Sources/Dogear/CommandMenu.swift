import DogearKit
import SwiftUI

struct LibraryCommand: Identifiable {
    /// Stable, for example "go.Recipes" or "export.markdown".
    let id: String
    let title: String
    let symbol: String
    let run: () -> Void
}

/// A Command-K menu: type to filter, arrow keys to move, Return to run.
struct CommandMenu: View {
    let commands: [LibraryCommand]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private static let rowHeight: CGFloat = 32
    private static let visibleRows = 8

    private var results: [LibraryCommand] {
        CommandMatch.rank(commands.map(\.title), query: query).map { commands[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($fieldFocused)
                .accessibilityLabel("Command")
                .onSubmit(runHighlighted)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
            Divider()
            list
        }
        .frame(width: 480)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    @ViewBuilder private var list: some View {
        let shown = results
        if shown.isEmpty {
            Text("No matching command")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight * 2)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { offset, command in
                            row(command, isHighlighted: offset == highlighted)
                        }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(shown.count), CGFloat(Self.visibleRows)) * Self.rowHeight + 12)
                .onChange(of: highlighted) { _, index in
                    guard shown.indices.contains(index) else { return }
                    proxy.scrollTo(shown[index].id)
                }
            }
        }
    }

    private func row(_ command: LibraryCommand, isHighlighted: Bool) -> some View {
        Button { run(command) } label: {
            Label(command.title, systemImage: command.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: Self.rowHeight)
                .background(isHighlighted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(command.id)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .handled }
        highlighted = min(max(highlighted + step, 0), count - 1)
        return .handled
    }

    private func runHighlighted() {
        let shown = results
        guard shown.indices.contains(highlighted) else { return }
        run(shown[highlighted])
    }

    private func run(_ command: LibraryCommand) {
        dismiss()
        // The next turn lets this sheet close first, so a command that opens a sheet does not collide with it.
        DispatchQueue.main.async { command.run() }
    }
}
