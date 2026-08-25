import DogearKit
import SwiftUI

/// One line the user pasted, and what the map made of it.
struct PlaceCandidate: Identifiable {
    let id = UUID()
    let query: PlaceQuery
    var place: Place?
    var isSelected: Bool
}

private enum PlacesImportStep: Equatable {
    case paste
    case searching(done: Int, total: Int)
    case review
    case saved(count: Int)
}

/// Saves restaurants and hotels that live in a note with no link. The user
/// pastes the lines, Dogear looks each one up, and nothing is saved until the
/// user has seen what the map found.
struct PlacesImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var step: PlacesImportStep = .paste
    @State private var candidates: [PlaceCandidate] = []
    @State private var folder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .paste: pasteStep
            case .searching(let done, let total): searchingStep(done: done, total: total)
            case .review: reviewStep
            case .saved(let count): savedStep(count: count)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            // Restaurants is where these notes belong, when the folder is still there.
            folder = model.store.library.folders.contains("Restaurants")
                ? "Restaurants" : Library.unsorted
        }
    }

    // MARK: Paste

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Places").font(.title3.weight(.semibold))
            Text("Paste one place per line. Write the city, a tilde, then the name. "
                 + "A line with only a name works too.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text("Lisbon, Portugal ~ Time Out Market")
                .font(.caption.monospaced()).foregroundStyle(.tertiary)
            folderPicker
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Find Places", action: search)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(PlaceParser.parse(text).isEmpty)
            }
        }
    }

    private var folderPicker: some View {
        Picker("Save to", selection: $folder) {
            ForEach(model.store.library.folders, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Searching

    private func searchingStep(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Looking up places").font(.title3.weight(.semibold))
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text("\(done) of \(total)").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check these places").font(.title3.weight(.semibold))
            Text("Nothing is saved yet. Turn off any line that found the wrong place.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach($candidates) { $candidate in
                    row($candidate)
                }
            }
            .frame(height: 240)
            .listStyle(.inset)
            folderPicker
            HStack {
                Button("Back") { step = .paste }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save \(selectedCount) Place\(selectedCount == 1 ? "" : "s")", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCount == 0)
            }
        }
    }

    private func row(_ candidate: Binding<PlaceCandidate>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let place = candidate.wrappedValue.place {
                Toggle(isOn: candidate.isSelected) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                        if let address = place.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.wrappedValue.query.searchText)
                        .foregroundStyle(.secondary).strikethrough()
                    Text("Not found on the map").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var selectedCount: Int {
        candidates.filter { $0.isSelected && $0.place != nil }.count
    }

    // MARK: Saved

    private func savedStep(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved").font(.title3.weight(.semibold))
            Text(count == 1 ? "Dogear saved 1 place." : "Dogear saved \(count) places.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Actions

    private func search() {
        let queries = PlaceParser.parse(text)
        step = .searching(done: 0, total: queries.count)
        Task {
            let resolver = MapKitPlaceResolver()
            var found: [PlaceCandidate] = []
            // One lookup at a time: the map service refuses a burst of them.
            for (index, query) in queries.enumerated() {
                let place = await resolver.resolve(query)
                found.append(PlaceCandidate(query: query, place: place, isSelected: place != nil))
                step = .searching(done: index + 1, total: queries.count)
            }
            candidates = found
            step = .review
        }
    }

    private func save() {
        let places = candidates.filter(\.isSelected).compactMap(\.place)
        let saved = model.importPlaces(places, to: folder)
        step = .saved(count: saved)
    }
}
