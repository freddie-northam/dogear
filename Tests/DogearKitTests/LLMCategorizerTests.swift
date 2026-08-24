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
    let categorizer = CategorizerFactory.make()
    if #available(macOS 26, *) {
        // The LLM path only engages when FoundationModels reports the on-device
        // model available at runtime, which this test cannot control either way.
        #expect(categorizer is KeywordCategorizer || categorizer is FallbackCategorizer)
        return
    }
    // Below macOS 26, FoundationModels is unavailable, so the factory always
    // returns the keyword path.
    #expect(categorizer is KeywordCategorizer)
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

@Test func primaryAnswerIsHonoredWhenValid() async {
    let categorizer = FallbackCategorizer(
        primary: FixedCategorizer(answer: "Recipes"),
        fallback: FixedCategorizer(answer: "Shows"),
        timeout: .seconds(5)
    )
    let result = await categorizer.categorize(FetchedMetadata(), url: URL(string: "https://a.com")!, folders: ["Recipes", "Shows"])
    #expect(result == "Recipes")
}

@Test func unsortedPrimaryAnswerFallsBack() async {
    let categorizer = FallbackCategorizer(
        primary: FixedCategorizer(answer: "Unsorted"),
        fallback: FixedCategorizer(answer: "Recipes"),
        timeout: .seconds(5)
    )
    let result = await categorizer.categorize(FetchedMetadata(), url: URL(string: "https://a.com")!, folders: ["Recipes", "Unsorted"])
    #expect(result == "Recipes")
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
