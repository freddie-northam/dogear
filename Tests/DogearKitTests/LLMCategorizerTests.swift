import Foundation
import Testing
@testable import DogearKit

private struct SlowCategorizer: Categorizer {
    func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? {
        try? await Task.sleep(for: .seconds(30))
        return "Recipes"
    }
}

private struct FixedCategorizer: Categorizer {
    let answer: String?
    func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? { answer }
}

@Test func factoryReturnsACategorizerOnEveryOS() {
    // On macOS 15 build machines this is the keyword path; on 26+ it may be the LLM.
    _ = CategorizerFactory.make()
}

@Test func fallbackUsedWhenPrimaryReturnsNil() async {
    let categorizer = FallbackCategorizer(
        primary: FixedCategorizer(answer: nil),
        fallback: FixedCategorizer(answer: "Articles"),
        timeout: .seconds(5)
    )
    let result = await categorizer.categorize(FetchedMetadata(), url: URL(string: "https://a.com")!, folders: ["Articles"])
    #expect(result == "Articles")
}

@Test func primaryTimeoutFallsBack() async {
    let categorizer = FallbackCategorizer(
        primary: SlowCategorizer(),
        fallback: FixedCategorizer(answer: "Shows"),
        timeout: .milliseconds(50)
    )
    let start = ContinuousClock.now
    let result = await categorizer.categorize(FetchedMetadata(), url: URL(string: "https://a.com")!, folders: ["Shows"])
    #expect(result == "Shows")
    #expect(ContinuousClock.now - start < .seconds(5))
}
