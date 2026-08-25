import Foundation

/// Asks a model to name the folders a library is actually made of.
///
/// `FolderSuggestions` can only offer folders the categorizer already knows,
/// so a library full of things it has no rule for gets no offer at all. This
/// reads the waiting bookmarks and proposes names from what is there.
///
/// It sends bookmark titles to the configured command. Every caller must be
/// behind an explicit opt-in.
public struct FolderPlanner: Sendable {
    let runner: CLIModelRunner
    /// Titles per assignment call. Measured: 40 titles answer in about eight
    /// seconds, where one call per bookmark would take minutes.
    let batchSize: Int
    /// Titles shown to the model when asking it to name folders. A sample is
    /// enough to see the shape of a library, and keeps the prompt small.
    let sampleSize: Int
    let maximumFolders: Int
    /// How many assignment calls run at once.
    let maximumConcurrentBatches: Int

    public init(runner: CLIModelRunner, batchSize: Int = 40, sampleSize: Int = 60,
                maximumFolders: Int = 5, maximumConcurrentBatches: Int = 3) {
        self.runner = runner
        self.batchSize = batchSize
        self.sampleSize = sampleSize
        self.maximumFolders = maximumFolders
        self.maximumConcurrentBatches = max(1, maximumConcurrentBatches)
    }

    public func plan(for bookmarks: [Bookmark], folders: [String]) async throws -> FolderPlan {
        let waiting = bookmarks.filter {
            $0.folder == Library.unsorted && !$0.isDone && !$0.manuallyFiled
        }
        guard !waiting.isEmpty else { return FolderPlan(suggestions: [], assignments: [:]) }

        let existing = folders.filter { $0 != Library.unsorted }
        let proposed = try await proposeNames(for: waiting, existing: existing)
        guard !proposed.isEmpty else { return FolderPlan(suggestions: [], assignments: [:]) }

        let choices = existing + proposed
        let batches = stride(from: 0, to: waiting.count, by: batchSize).map {
            Array(waiting[$0..<min($0 + batchSize, waiting.count)])
        }
        // The batches do not depend on each other, and the time is spent
        // waiting on a command rather than working, so run several at once.
        // Measured on a 212 link library: about 133 seconds one at a time,
        // against about 40 with three in flight. Bounded, because a tool with
        // a rate limit answers a flood with errors rather than answers.
        var assignments: [UUID: String] = [:]
        try await withThrowingTaskGroup(of: [UUID: String].self) { group in
            var next = batches.makeIterator()
            var running = 0
            while running < maximumConcurrentBatches, let batch = next.next() {
                group.addTask { try await assign(batch, choices: choices) }
                running += 1
            }
            while let assigned = try await group.next() {
                assignments.merge(assigned) { current, _ in current }
                if let batch = next.next() {
                    group.addTask { try await assign(batch, choices: choices) }
                }
            }
        }

        // Count only the folders that do not exist yet: those are the ones the
        // user is being asked to make. Counts come from real assignments, so
        // the number next to a folder is the number that would move into it.
        let byID = Dictionary(uniqueKeysWithValues: waiting.map { ($0.id, $0) })
        var suggestions: [FolderSuggestion] = []
        for name in proposed {
            let matched = assignments.filter { $0.value == name }.keys.compactMap { byID[$0] }
            guard !matched.isEmpty else { continue }
            suggestions.append(FolderSuggestion(
                name: name,
                count: matched.count,
                examples: matched.sorted { $0.createdAt > $1.createdAt }.prefix(3).map(\.title)
            ))
        }
        suggestions.sort { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        return FolderPlan(suggestions: suggestions, assignments: assignments)
    }

    // MARK: Prompts

    private func proposeNames(for waiting: [Bookmark], existing: [String]) async throws -> [String] {
        let sample = waiting.prefix(sampleSize).map { "- " + oneLine($0.title) }.joined(separator: "\n")
        let prompt = """
            These saved links do not fit any existing folder. \
            Existing folders: \(existing.joined(separator: ", ")).
            Propose at most \(maximumFolders) new folder names that would group them well. \
            Use short plain names. Do not repeat an existing folder. \
            Reply with ONLY a comma separated list of names and nothing else.

            \(sample)
            """
        let answer = try await runner.run(prompt: prompt)
        return cleanNames(answer, existing: existing)
    }

    func assign(_ batch: [Bookmark], choices: [String]) async throws -> [UUID: String] {
        let numbered = batch.enumerated()
            .map { "\($0.offset + 1). \(oneLine($0.element.title))" }
            .joined(separator: "\n")
        let prompt = """
            Assign each numbered link to exactly one folder from this list: \
            \(choices.map(oneLine).joined(separator: ", ")), \(Library.unsorted).
            Use \(Library.unsorted) when genuinely unclear. \
            Reply with ONLY lines of the form N=Folder, one per link, nothing else.

            \(numbered)
            """
        let answer = try await runner.run(prompt: prompt)
        return parseAssignments(answer, batch: batch, choices: choices)
    }

    // MARK: Parsing

    /// Reads `N=Folder` lines. A line that names a folder outside the list, or
    /// a number outside the batch, is dropped: the hard rule is that a
    /// categorizer never invents a folder, and a model is not exempt.
    func parseAssignments(_ answer: String, batch: [Bookmark],
                          choices: [String]) -> [UUID: String] {
        var assignments: [UUID: String] = [:]
        for line in answer.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let number = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  number >= 1, number <= batch.count else { continue }
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard let folder = choices.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            else { continue }
            assignments[batch[number - 1].id] = folder
        }
        return assignments
    }

    /// Reads a comma separated list of names, dropping anything unusable: an
    /// empty name, a duplicate, one the library already has, or one long
    /// enough to be a sentence rather than a folder.
    func cleanNames(_ answer: String, existing: [String]) -> [String] {
        var names: [String] = []
        for raw in answer.split(separator: ",") {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.`"))
            guard !name.isEmpty, name.count <= 30, isPlainName(name),
                  name.caseInsensitiveCompare(Library.unsorted) != .orderedSame,
                  !existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
                  !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            else { continue }
            names.append(name)
        }
        return Array(names.prefix(maximumFolders))
    }

    /// True when a name is ordinary printable text on one line.
    ///
    /// A page writes its own title, and those titles are what the model is
    /// asked to name folders from, so a proposed name is downstream of text an
    /// attacker controls. A name carrying a newline would be pasted straight
    /// into the next prompt, where a line like `2=Music` is exactly the shape
    /// the reply is parsed against: one hostile title could then steer where
    /// every other link is filed, and the plan is built before anyone sees it.
    /// Such a name is refused outright rather than repaired, because the user
    /// approves what they are shown and it must be what gets created.
    func isPlainName(_ name: String) -> Bool {
        !name.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }

    /// Titles arrive from pages and can carry newlines, which would break the
    /// one-line-per-link shape the reply is parsed against.
    private func oneLine(_ title: String) -> String {
        title.components(separatedBy: .newlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
