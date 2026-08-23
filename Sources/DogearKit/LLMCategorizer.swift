import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct FallbackCategorizer: Categorizer {
    let primary: Categorizer
    let fallback: Categorizer
    let timeout: Duration

    public init(primary: Categorizer, fallback: Categorizer, timeout: Duration = .seconds(5)) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
    }

    public func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? {
        let primaryResult = await withTaskGroup(of: String??.self) { group -> String?? in
            group.addTask { await primary.categorize(metadata, url: url, folders: folders) }
            group.addTask { try? await Task.sleep(for: timeout); return String??.none }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if case let .some(answer?) = primaryResult, answer != Library.unsorted, folders.contains(answer) {
            return answer
        }
        return await fallback.categorize(metadata, url: url, folders: folders)
    }
}

public enum CategorizerFactory {
    public static func make() -> Categorizer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return FallbackCategorizer(primary: LLMCategorizer(), fallback: KeywordCategorizer())
        }
        #endif
        return KeywordCategorizer()
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct LLMCategorizer: Categorizer {
    func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? {
        let text = [metadata.title, metadata.description, metadata.author]
            .compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You file saved links into folders. Answer with exactly one folder name \
            from the list. Answer "Unsorted" when unsure.
            """)
        let prompt = "Folders: \(folders.joined(separator: ", "))\nLink text:\n\(text)\nFolder:"
        guard let answer = try? await session.respond(to: prompt).content
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return folders.first { $0.caseInsensitiveCompare(answer) == .orderedSame }
    }
}
#endif
