/// Runs `body` on every item with at most `limit` running at once.
/// Returns the results in the order they finish.
public func boundedMap<T: Sendable, R: Sendable>(
    _ items: [T], limit: Int, _ body: @escaping @Sendable (T) async -> R
) async -> [R] {
    await withTaskGroup(of: R.self) { group in
        var results: [R] = []
        var pending = items.makeIterator()
        for _ in 0..<limit {
            guard let item = pending.next() else { break }
            group.addTask { await body(item) }
        }
        for await result in group {
            results.append(result)
            if let item = pending.next() { group.addTask { await body(item) } }
        }
        return results
    }
}
