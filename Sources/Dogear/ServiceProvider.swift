import AppKit
import DogearKit

final class ServiceProvider: NSObject {
    private let capture: @MainActor (String) -> Void

    init(capture: @escaping @MainActor (String) -> Void) {
        self.capture = capture
    }

    @objc func saveToDogear(_ pasteboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }
        let capture = capture
        Task { @MainActor in capture(text) }
    }
}
