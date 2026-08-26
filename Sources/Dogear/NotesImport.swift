// Reading Apple Notes for links: the import's own state, the two
// AppleScript reads, and the sheet that asks for consent and folders.
import DogearKit
import SwiftUI

enum NotesImportState: Equatable {
    case confirm
    case running(String)
    case choosing([NotesFolder])
    case finished(String)
}

/// One Notes folder, as returned by the Notes scripting dictionary: a
/// read-only id (stable across renames) and a display name.
struct NotesFolder: Identifiable, Equatable {
    let id: String
    let name: String
}

/// One alert, one state: the collision message replaces the rename prompt's
/// content in place instead of a second `.alert` firing from the first's
/// own dismissal, which SwiftUI can drop silently.

func readNotesFolders() -> [NotesFolder]? {
    let source = "tell application \"Notes\" to get {id of every folder, name of every folder}"
    var errorInfo: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
          errorInfo == nil,
          descriptor.numberOfItems == 2,
          let ids = descriptor.atIndex(1),
          let names = descriptor.atIndex(2),
          ids.numberOfItems == names.numberOfItems else { return nil }
    let count = ids.numberOfItems
    guard count > 0 else { return [] }
    return (1...count).compactMap { index -> NotesFolder? in
        guard let id = ids.atIndex(index)?.stringValue,
              let name = names.atIndex(index)?.stringValue else { return nil }
        return NotesFolder(id: id, name: name)
    }
}

/// Reads every non-password-protected note body in one folder, over Apple
/// events, on the main thread. When `secondsSince` is given, only notes
/// modified within that many seconds of now are read (an incremental read);
/// nil means a full read. Returns nil when the folder cannot be read.
func readNotesBody(folderID: String, secondsSince: Int?) -> String? {
    let escapedID = folderID
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    var whose = "password protected is false"
    var cutoffLine = ""
    if let secondsSince {
        cutoffLine = "set cutoff to (current date) - \(secondsSince)\n"
        whose += " and modification date > cutoff"
    }
    let source = "tell application \"Notes\"\n" +
        "set f to first folder whose id is \"\(escapedID)\"\n" +
        cutoffLine +
        "get body of every note of f whose \(whose)\n" +
        "end tell"
    var errorInfo: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
          errorInfo == nil else { return nil }
    // A list descriptor is 1-indexed. Zero items covers both an empty folder
    // and a scalar result, whose text still comes back as stringValue.
    guard descriptor.numberOfItems > 0 else { return descriptor.stringValue ?? "" }
    return (1...descriptor.numberOfItems)
        .compactMap { descriptor.atIndex($0)?.stringValue }
        .joined(separator: "\n")
}

struct NotesImportSheet: View {
    @Binding var state: NotesImportState
    @Binding var selectedFolderIDs: Set<String>
    let continueToFolders: () -> Void
    let run: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        if case .choosing = state { return "Which folders?" }
        return "Import from Notes"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            switch state {
            case .confirm:
                Text("Dogear reads your notes on this Mac to find links. macOS asks you for permission one time. Nothing leaves your Mac.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Continue", action: continueToFolders)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .running(let label):
                ProgressView(label)
                // Cancel cannot interrupt the in-flight Apple event (the
                // call is synchronous on the main actor); it only lets the
                // user dismiss once the event has returned.
                Button("Cancel") { state = .confirm }
            case .choosing(let folders):
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(folders) { folder in
                            Toggle(folder.name, isOn: Binding(
                                get: { selectedFolderIDs.contains(folder.id) },
                                set: { isOn in
                                    if isOn { selectedFolderIDs.insert(folder.id) }
                                    else { selectedFolderIDs.remove(folder.id) }
                                }
                            ))
                        }
                    }
                }
                .frame(maxHeight: 220)
                HStack {
                    Button("Select all") { selectedFolderIDs = Set(folders.map(\.id)) }
                    Button("Select none") { selectedFolderIDs = [] }
                    Spacer()
                }
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Import", action: run)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedFolderIDs.isEmpty)
                }
            case .finished(let message):
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
