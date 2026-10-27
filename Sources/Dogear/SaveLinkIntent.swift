import AppIntents
import DogearKit
import Foundation

struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Links to Dogear"
    static var description = IntentDescription(
        "Saves every web link in the text you give it. A link already saved moves to the top.")
    static var openAppWhenRun = true

    @Parameter(title: "Text or Link")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let model = try await Self.readyModel()
        return .result(value: model.captureWithoutWindow(text: text).new.count)
    }

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
