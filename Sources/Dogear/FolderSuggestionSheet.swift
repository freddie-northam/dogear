import DogearKit
import SwiftUI

/// Offers new folders for the links in Unsorted. Nothing changes until the user clicks Create Folders.
struct FolderSuggestionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [FolderSuggestion]?
    @State private var chosen: Set<String> = []
    @State private var filed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggest Folders").font(.title3.weight(.semibold))
            if let filed {
                Text("Dogear created \(count(chosen.count, "folder")) and filed \(count(filed, "bookmark")).")
                    .font(.callout)
                footer { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if let suggestions, suggestions.isEmpty {
                Text("No new folders fit the links in Unsorted.").font(.callout).foregroundStyle(.secondary)
                footer { Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if let suggestions {
                Text("These folders would take links out of Unsorted. Nothing changes until you create them.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(suggestions, id: \.folder) { suggestion in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(suggestion.folder) },
                        set: { if $0 { chosen.insert(suggestion.folder) } else { chosen.remove(suggestion.folder) } }
                    )) {
                        HStack {
                            Image(systemName: folderSymbol(for: suggestion.folder))
                                .foregroundStyle(folderColor(for: suggestion.folder))
                            Text(suggestion.folder)
                            Spacer()
                            Text(count(suggestion.ids.count, "link")).foregroundStyle(.secondary)
                        }
                    }
                }
                footer {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Create Folders") {
                        filed = model.store.accept(suggestions.filter { chosen.contains($0.folder) })
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            let found = await FolderSuggestions.suggest(for: model.store.library)
            chosen = Set(found.map(\.folder))
            suggestions = found
        }
    }

    private func footer(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack { Spacer(); buttons() }
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
