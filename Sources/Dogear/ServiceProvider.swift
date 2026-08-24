import AppKit
import DogearKit

/// Receives the Save to Dogear service. NSApp.servicesProvider does not
/// retain its provider, so DogearApp holds the strong reference.
final class ServiceProvider: NSObject {
    private let capture: @MainActor (String) -> Void

    init(capture: @escaping @MainActor (String) -> Void) {
        self.capture = capture
    }

    @objc func saveToDogear(_ pasteboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }
        let urls = URLCleaner.allHTTPURLs(in: text)
        guard !urls.contains(where: { $0.user != nil || $0.password != nil }) else {
            error.pointee = "Remove the username or password from this link before saving it."
            return
        }
        guard !urls.isEmpty else {
            error.pointee = "Dogear saves http and https web links."
            return
        }
        let capture = capture
        Task { @MainActor in capture(text) }
    }
}
