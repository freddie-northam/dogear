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
        let model = try await AppModel.ready()
        return .result(value: model.captureWithoutWindow(text: text).new.count)
    }
}

enum SaveLinkError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case libraryUnavailable
    case noSuchFolder(String)
    case noSuchBookmark

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .libraryUnavailable: "Dogear could not open your library."
        case .noSuchFolder(let name): "Dogear has no folder named \(name)."
        case .noSuchBookmark: "Dogear could not find that bookmark."
        }
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
        AppShortcut(
            intent: GetPickIntent(),
            phrases: ["Get a pick from \(.applicationName)"],
            shortTitle: "Get a Pick",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: FindBookmarksIntent(),
            phrases: ["Find bookmarks in \(.applicationName)"],
            shortTitle: "Find Bookmarks",
            systemImageName: "magnifyingglass"
        )
    }
}
