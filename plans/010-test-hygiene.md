# Plan 010: Make the test suite assert what it claims and leave no litter

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4bac044..HEAD -- Tests/DogearKitTests/`
> The test directory is shared with other in-flight plans; a diff that touches
> ONLY `EnrichmentServiceTests.swift` is expected (plan 006) and is not a
> stop. Any other changed test file: compare excerpts, STOP on mismatch.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `4bac044`, 2026-08-24

## Why this matters

Four credibility leaks in an otherwise strong suite. Three `pick()` tests loop 20 times over a candidate set that collapses to exactly one eligible bookmark, so 60 rolls exercise a deterministic path while the real invariant (the draw is random among the ten OLDEST) is unguarded: widening `prefix(10)` to the whole library would stay green. Two tests assert nothing: `factoryReturnsACategorizerOnEveryOS` has no `#expect`, and `neverReturnsAFolderOutsideTheList` accepts every value the code can return. Every `swift test` run leaks ~35 temp directories including multi-megabyte JSON files. And two wall-clock assertions (200 ms load, 100 ms search) run on every PR on shared CI runners where a noisy neighbour can fail them for reasons unrelated to the diff.

## Current state

- `Tests/DogearKitTests/BookmarkStoreTests.swift`: `tempDir()` helper at line 5 (creates `dogear-test-<uuid>` under `temporaryDirectory`, never removed); 20-roll loops at lines 252, 261, 458 inside `pickNeverReturnsADoneBookmark`, `pickExcludesTheGivenIDWhenAnotherCandidateExists`, `pickPrefersFiledAndOldest`; timing assertions at lines 392 (`< .milliseconds(200)`) and 396 (`< .milliseconds(100)`) inside the 5,000-bookmark test.
- `Tests/DogearKitTests/LLMCategorizerTests.swift:17-20`:

```swift
@Test func factoryReturnsACategorizerOnEveryOS() {
    // On macOS 15 build machines this is the keyword path; on 26+ it may be the LLM.
    _ = CategorizerFactory.make()
}
```

- `Tests/DogearKitTests/KeywordCategorizerTests.swift:87-91`:

```swift
@Test func neverReturnsAFolderOutsideTheList() async {
    let metadata = FetchedMetadata(title: "Creamy pasta recipe", description: nil)
    let folder = await KeywordCategorizer().categorize(metadata, url: URL(string: "https://a.com")!, folders: ["Watchlist", "Unsorted"])
    #expect(folder == nil || folder == "Watchlist" || folder == "Unsorted")
}
```

- 11 `temporaryDirectory` uses across the test files (BookmarkStoreTests, EnrichmentServiceTests, ThumbnailCacheTests).
- `BookmarkStore.pick(excluding:)` semantics: filed-before-unsorted, then random among the 10 oldest by `createdAt` of the preferred pool. `addForTesting(urlString:)` exists (internal, skips saves) and creates bookmarks with `createdAt: Date()`; for distinct dates you may construct `Bookmark` values directly and append through the public `update`/`add` path, or set `createdAt` via the memberwise init and insert with `addForTesting`-style access if available. Read the file to choose.
- Canary tests are gated with `.enabled(if: ProcessInfo.processInfo.environment["CANARY"] != nil)` in `CanaryTests.swift`; that is the pattern for the perf gate.

Conventions: no em dashes; Conventional Commits, no AI attribution; Swift Testing.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Full | `swift test` | exit 0, zero warnings |
| Perf-gated | `PERF=1 swift test --filter BookmarkStoreTests` | timing tests run and pass |
| Litter check | `ls /private/tmp /var/folders 2>/dev/null \| grep -c dogear-test` before/after | count does not grow |

## Scope

**In scope**: `Tests/DogearKitTests/BookmarkStoreTests.swift`, `LLMCategorizerTests.swift`, `KeywordCategorizerTests.swift`, `ThumbnailCacheTests.swift`, and a new `Tests/DogearKitTests/TempDirectory.swift` helper. `EnrichmentServiceTests.swift` is being edited by plan 006 concurrently: do NOT touch it (leave its temp-dir usage for a follow-up).

**Out of scope**: any file under `Sources/`; `CanaryTests.swift`; CI workflow files.

## Git workflow

- Commit in the worktree; `test:` Conventional Commits. Do NOT push.

## Steps

### Step 1: Shared temp directory helper

Create `Tests/DogearKitTests/TempDirectory.swift`:

```swift
import Foundation

/// A per-test scratch directory that removes itself. Hold it for the test's
/// lifetime; the directory is gone when the value is deinitialized.
final class TempDirectory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dogear-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
```

Replace `tempDir()` in `BookmarkStoreTests.swift` and the inline `temporaryDirectory` patterns in `ThumbnailCacheTests.swift` so each test holds a `let temp = TempDirectory()` and passes `temp.url`. Keep the test bodies otherwise identical.

**Verify**: `swift test --filter "BookmarkStoreTests|ThumbnailCacheTests"` → all pass. Count `dogear-test-*` directories under `$(getconf DARWIN_USER_TEMP_DIR)` before and after a run: the count must not grow.

### Step 2: Real pick assertions

Collapse each 20-roll loop to a single call (the candidate set is one element; one roll proves it). Add `pickDrawsOnlyFromTheTenOldest`: create 15 not-done bookmarks with strictly increasing distinct `createdAt` values (seconds apart), sample `store.pick()` 50 times, collect the ids, and assert (a) every sampled id is within the 10 oldest and (b) at least 2 distinct ids were sampled (proving it is still a draw). Read `BookmarkStore` to decide how to inject distinct `createdAt` values through existing test-visible API; do not add store API.

**Verify**: `swift test --filter BookmarkStoreTests` → all pass including the new test.

### Step 3: Make the two empty tests assert

- `factoryReturnsACategorizerOnEveryOS`: on this build machine (no FoundationModels), assert `CategorizerFactory.make() is KeywordCategorizer`. Guard for future OSes: `if #available(macOS 26, *) { /* may be LLM; assert it is a Categorizer and return */ }` before the keyword assertion, so the test stays truthful when someone builds on Xcode 26.
- `neverReturnsAFolderOutsideTheList`: the metadata is a recipe; the folder list deliberately excludes Recipes. Assert `folder == nil` (the categorizer must not invent "Recipes") and, as the general rule, `folder.map { ["Watchlist"].contains($0) } != false` (Unsorted is never returned directly by the keyword categorizer; check its implementation and assert `folder != "Unsorted"` too).

**Verify**: `swift test --filter "LLMCategorizerTests|KeywordCategorizerTests"` → all pass.

### Step 4: Gate the timing assertions

In the 5,000-bookmark test keep the functional half unconditional (load succeeds with 5,000 bookmarks; search returns the expected hit) and move the two `elapsed < ...` expectations behind `if ProcessInfo.processInfo.environment["PERF"] != nil { ... }`. Add a comment: the spec's benchmark table is verified by `PERF=1 swift test`, not on every PR, because shared runners are noisy.

**Verify**: `swift test` → all pass, zero warnings. `PERF=1 swift test --filter BookmarkStoreTests` → passes with the timing assertions active.

## Test plan

This plan IS the test plan; every step's verify line is the gate.

## Done criteria

- [ ] `swift test` exits 0, zero warnings; `PERF=1 swift test --filter BookmarkStoreTests` exits 0.
- [ ] `grep -c "for _ in 0..<20" Tests/DogearKitTests/BookmarkStoreTests.swift` → 0.
- [ ] `grep -n "#expect" Tests/DogearKitTests/LLMCategorizerTests.swift` shows an expectation inside `factoryReturnsACategorizerOnEveryOS`.
- [ ] Temp-dir count does not grow across a run (report the before/after numbers).
- [ ] `git status --porcelain` shows only in-scope files; `EnrichmentServiceTests.swift` untouched.

## STOP conditions

- A test-visible way to create bookmarks with distinct `createdAt` does not exist without adding store API (report; the reviewer will decide on a test-only initializer).
- Collapsing a pick loop exposes a real flake (the single call fails intermittently): report the test and observed behavior instead of re-adding the loop.

## Maintenance notes

- `EnrichmentServiceTests.swift` still uses inline temp dirs; migrate it to `TempDirectory` after plan 006 lands (one-line follow-up).
- Add a `perf` CI job (`PERF=1`) in the publication plan so the benchmark table is still exercised regularly.
