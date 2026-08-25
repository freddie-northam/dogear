import DogearKit
import SwiftUI

/// Shows what a plan would do, and files it only if the user says so.
///
/// The count next to a folder is the number of waiting links that would move
/// into it, worked out by actually assigning them. The examples are there so
/// the count is something you can check rather than something you trust.
struct FolderSuggestionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let plan: FolderPlan
    /// Reported back so the window can say what happened, the same way
    /// File These for Me does.
    let onFiled: (Int) -> Void
    /// Folders the user has ticked. Everything starts accepted: the plan was
    /// asked for, so the common case is taking it.
    @State private var accepted: Set<String> = []

    private var acceptedCount: Int {
        plan.suggestions.filter { accepted.contains($0.name) }.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested folders").font(.headline)
                Text("Dogear read the links waiting in Unsorted. Pick the folders worth "
                     + "having, and it files them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.suggestions, id: \.name) { suggestion in
                        Toggle(isOn: binding(for: suggestion.name)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(suggestion.name)  ")
                                    + Text("\(suggestion.count) link\(suggestion.count == 1 ? "" : "s")")
                                    .foregroundColor(.secondary)
                                ForEach(suggestion.examples, id: \.self) { example in
                                    Text(example)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 320)

            Divider()

            HStack {
                Text(acceptedCount == 0
                     ? "Nothing selected."
                     : "Files \(acceptedCount) link\(acceptedCount == 1 ? "" : "s").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create and File") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(accepted.isEmpty)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear { accepted = Set(plan.suggestions.map(\.name)) }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { accepted.contains(name) },
            set: { isOn in
                if isOn { accepted.insert(name) } else { accepted.remove(name) }
            }
        )
    }

    /// Makes the folders first, because the store refuses to file into one
    /// that does not exist, then files only the links bound for them.
    private func apply() {
        let names = plan.suggestions.map(\.name).filter { accepted.contains($0) }
        for name in names { model.store.addFolder(name) }
        let assignments = plan.assignments
            .filter { names.contains($0.value) }
            .map { (id: $0.key, folder: $0.value) }
        let filed = model.store.autoFile(assignments)
        onFiled(filed)
        dismiss()
    }
}
