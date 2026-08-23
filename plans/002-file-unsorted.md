# Plan 002: Make File These for Me safe, batched, and visible

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 5f06577..HEAD -- Sources/Dogear/AppModel.swift Sources/DogearKit/BookmarkStore.swift Sources/Dogear/LibraryWindow.swift Tests/DogearKitTests/BookmarkStoreTests.swift`
> On any change to these files since `5f06577`, compare the "Current state"
> excerpts against the live code; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 001 (DONE)
- **Category**: bug
- **Planned at**: commit `5f06577`, 2026-08-24

## Why this matters

"File These for Me" (Unsorted folder context menu) re-runs the categorizer over the Unsorted inbox. Three defects: (1) `BookmarkStore.autoFile` ignores `manuallyFiled` and current folder membership, so a user who drags a card out of Unsorted while the run is in flight has that choice silently overwritten when the loop reaches the stale snapshot entry; (2) each `autoFile` call runs `mutated()`, which encodes and writes the ENTIRE library to disk, so filing 200 of 300 unsorted links performs 200 full-store writes and 200 UI invalidations for one menu click; (3) the call site discards the returned count, so the user gets no confirmation, no number, and no signal when nothing was filed. On the macOS 26 LLM path each categorize call can take seconds, making the silent, unguarded run minutes long.

## Current state

Relevant files:

- `Sources/Dogear/AppModel.swift` — `fileUnsorted()` at lines 50-69 (excerpt below); the batching pattern to copy lives in `capture(urls:)` directly below it, which calls `store.add(urls:)` once for the whole batch.
- `Sources/DogearKit/BookmarkStore.swift` — `autoFile(id:to:)` around line 118: guards only that the id exists and the folder exists, then `mutated()` per call. `add(urls:)` (one `mutated()` per batch) is the exemplar. `bookmarks(in:)` returns not-done bookmarks in a folder.
- `Sources/Dogear/LibraryWindow.swift` — the call site inside the sidebar context menu: `Button { Task { await model.fileUnsorted() } } label: { Label("File These for Me", systemImage: "sparkles") }`, near line 136. The Notes import in the same file shows the feedback pattern: `NotesImportState` enum with `.finished(String)` driving a sheet.
- `Tests/DogearKitTests/BookmarkStoreTests.swift` — store tests, Swift Testing style.

`AppModel.fileUnsorted()` today (`Sources/Dogear/AppModel.swift:50-69`):

```swift
/// Re-runs the categorizer over every not-done Unsorted bookmark against
/// the current folder list. Returns how many were filed.
func fileUnsorted() async -> Int {
    let categorizer = CategorizerFactory.make()
    let unsorted = store.bookmarks(in: Library.unsorted)
    var filed = 0
    for bookmark in unsorted {
        let metadata = FetchedMetadata(
            title: bookmark.title, author: bookmark.author,
            description: bookmark.note, source: bookmark.source)
        guard let url = URL(string: bookmark.url) else { continue }
        let folders = store.library.folders
        if let folder = await categorizer.categorize(metadata, url: url, folders: folders),
           folder != Library.unsorted {
            store.autoFile(id: bookmark.id, to: folder)
            filed += 1
        }
    }
    return filed
}
```

Conventions: no em dashes anywhere; Conventional Commits, imperative capitalized subject, no AI attribution; new stored fields optional; STE for user-facing copy (short sentences, active voice); kit logic test-first.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused tests | `swift test --filter BookmarkStoreTests` | all pass |
| Full tests | `swift test` | exit 0, zero warnings |
| Build | `swift build` | Build complete |

## Scope

**In scope**:

- `Sources/DogearKit/BookmarkStore.swift` (change `autoFile` into a batch API)
- `Sources/Dogear/AppModel.swift` (`fileUnsorted` only)
- `Sources/Dogear/LibraryWindow.swift` (the call site and its feedback only)
- `Tests/DogearKitTests/BookmarkStoreTests.swift`

**Out of scope**:

- `EnrichmentService.swift`, `Categorizer.swift`, the capture path, the Notes import implementation.
- Parallelizing the categorize loop (serial is fine; only the writes were the problem).

## Git workflow

- Commit in the worktree; one `fix:` Conventional Commit (or one per logical unit). Do NOT push.

## Steps

### Step 1: Batch autoFile in the store

Replace `autoFile(id:to:)` with `autoFile(_ assignments: [(id: UUID, folder: String)])`:

- For each assignment: skip when the id is missing, when the bookmark is `manuallyFiled`, when its folder is no longer `Library.unsorted`, or when the target folder is not in `library.folders`.
- Apply all surviving assignments, then call `mutated()` AT MOST ONCE, and only if at least one assignment applied.
- Return the number applied.
- Keep the doc comment's contract: filing without claiming the user chose the folder.

**Verify**: `swift build` → Build complete.

### Step 2: Tests for the batch semantics

In `BookmarkStoreTests.swift` add:

1. `autoFileBatchWritesOnce` — seed 3 unsorted bookmarks, count `onChange` firings via the existing closure hook, batch-file all 3 to "Recipes", `#expect` the change count increased by exactly 1 and all 3 moved.
2. `autoFileSkipsManuallyFiledAndMoved` — seed 3 unsorted; `refile` one to "Shows" (sets manuallyFiled) and `autoFile`-batch all three ids to "Recipes"; the refiled one stays in "Shows", the applied count is 2.
3. `autoFileSkipsUnknownFolder` — an assignment to a folder not in the list applies zero and fires no change.

**Verify**: `swift test --filter BookmarkStoreTests` → all pass including 3 new.

### Step 3: Collect-then-apply in fileUnsorted

Rewrite the loop to collect `(id, folder)` decisions without touching the store, then call the batch `autoFile` once after the loop. Keep the per-bookmark categorize awaits serial. Return the applied count from the store call (not the collected count), so mid-run user refile is reflected in the number reported.

**Verify**: `swift build` → Build complete.

### Step 4: Surface the result

At the LibraryWindow call site, capture the count and show it with the existing alert idiom in that file (a simple `@State private var fileForMeResult: String?` plus one `.alert` using the same `Binding(get:set:)` pattern the Storage Error alert uses). Copy, STE, no em dashes:

- count > 0: `"Dogear filed N bookmarks."` (singular: `"Dogear filed 1 bookmark."`)
- count == 0: `"No matches. Add folders that fit your links, then try again."`

**Verify**: `swift build` → Build complete. Then `swift test` full suite → all pass, zero warnings.

## Test plan

Covered in Step 2; pattern: existing store tests using `onChange` and `refile`.

## Done criteria

- [ ] `swift test` exits 0; the 3 new tests exist and pass.
- [ ] `grep -n "func autoFile" Sources/DogearKit/BookmarkStore.swift` shows only the batch signature.
- [ ] `grep -n "await model.fileUnsorted()" Sources/Dogear/LibraryWindow.swift` shows the result is assigned, not discarded.
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- The excerpts do not match the live code (drift).
- The `onChange`-counting test approach fails because the hook fires differently than expected after plan 001's merge (report what you observe).
- Surfacing the count appears to require restructuring `NotesImportState` or the sheet flow (it does not; use a plain alert).

## Maintenance notes

- Plan 013 (Notes importer v2) will reuse the batch `autoFile` shape if it ever auto-files on import; keep the skip rules in one place.
- Reviewer: check the applied-count-vs-collected-count distinction in Step 3 and the singular/plural copy.
