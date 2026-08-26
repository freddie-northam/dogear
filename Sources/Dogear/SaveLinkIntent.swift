import AppIntents
import DogearKit
import Foundation

/// Puts capture in Shortcuts, so a link can be saved by an automation rather
/// than by hand. The Services item covers one link the user has selected;
/// this covers the batch nobody wants to paste one at a time.
struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Links to Dogear"
    static var description = IntentDescription(
        "Saves every web link in the text you give it. A link already saved moves to the top.")
    /// The library lives in the app, and one process must own the file.
    static var openAppWhenRun = true

    @Parameter(title: "Text or Link")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let model = try await Self.readyModel()
        return .result(value: model.captureWithoutWindow(text: text).new)
    }

    /// The app may still be starting when the intent runs, so wait for the
    /// library rather than fail on a race the user cannot see.
    @MainActor
    private static func readyModel() async throws -> AppModel {
        for _ in 0..<20 {
            if let model = AppModel.shared { return model }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw SaveLinkError.libraryUnavailable
    }
}

enum SaveLinkError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case libraryUnavailable

    var localizedStringResource: LocalizedStringResource {
        "Dogear could not open your library."
    }
}

struct DogearShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: ["Save links to \(.applicationName)"],
            shortTitle: "Save Links",
            systemImageName: "bookmark"
        )
    }
}
