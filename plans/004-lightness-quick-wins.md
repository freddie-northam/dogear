# Plan 004: Cache decoded thumbnails and compute folder counts in one pass

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 2b471d7..HEAD -- Sources/DogearKit/ThumbnailCache.swift Sources/DogearKit/BookmarkStore.swift Sources/Dogear/LibraryWindow.swift Sources/Dogear/CapturePopover.swift Tests/DogearKitTests/ThumbnailCacheTests.swift Tests/DogearKitTests/BookmarkStoreTests.swift`
> On any change since `2b471d7`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `2b471d7`, 2026-08-24

## Why this matters

Dogear's product bar is "one of the lightest apps on the system". Two hot paths violate it. First, every SwiftUI body evaluation that shows a thumbnail calls `NSImage(contentsOf:)` directly — a synchronous file read plus JPEG decode on the main thread — and bodies re-evaluate on every store mutation, hover change, and scroll cell materialization. With enrichment landing (4 concurrent fetches, each ending in a store write) a visible grid re-decodes every on-screen thumbnail per completed fetch; this is the likely scroll-hitch source. Second, the sidebar badges call `favorites()` (filter + sort), `archive()` (filter + sort), and `bookmarks(in:)` per folder row on every render, and the popover's counts line repeats the same scans: one sidebar pass over a 5,000-bookmark library is ~35,000 element visits plus two sorts, re-run per mutation.

## Current state

Relevant files:

- `Sources/DogearKit/ThumbnailCache.swift` — struct with `fileURL(for:)`, `store(_:for:)` (downsamples to 600px JPEG), `exists(for:)`, `remove(for:)`. No decoded-image cache. Excerpt of the head of the file:

```swift
public struct ThumbnailCache: Sendable {
    let directory: URL

    /// Cards render at ~220 points, so 600 pixels covers Retina with room to
    /// spare; full-size og:images measured 200 MB across a real library.
    static let maxPixelSize = 600

    public init(directory: URL) throws { ... }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
    }
```

- `Sources/Dogear/LibraryWindow.swift` — three thumbnail read sites: the grid card (`if bookmark.hasThumbnail, let image = NSImage(contentsOf: model.thumbnails.fileURL(for: bookmark.id))` inside `BookmarkCard`), the list row badge (same pattern inside `BookmarkListRow`), and the sidebar badges at lines 112/123/134:

```swift
.badge(model.store.favorites().count)      // line 112
.badge(model.store.bookmarks(in: folder).count)  // line 123, inside ForEach over folders
.badge(model.store.archive().count)        // line 134
```

- `Sources/Dogear/CapturePopover.swift` — the pick badge reads `NSImage(contentsOf: model.thumbnails.fileURL(for: pick.id))`; `countsLine` calls `model.store.bookmarks(in: folder).count` per folder.
- `Sources/DogearKit/BookmarkStore.swift` — has `bookmarks(in:)`, `favorites()`, `archive()`. No counts accessor.
- Tests: `ThumbnailCacheTests.swift`, `BookmarkStoreTests.swift`, Swift Testing style.

Conventions: `NSCache` is Foundation (allowed; zero third-party rule intact). `ThumbnailCache` is a struct today — converting it to a `final class` is acceptable and expected here (NSCache is a reference; the app creates exactly one instance in `AppModel`). No em dashes; Conventional Commits; no AI attribution; kit logic test-first.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter "ThumbnailCacheTests\|BookmarkStoreTests"` | all pass |
| Full | `swift test` | exit 0, zero warnings |
| Build | `swift build` | Build complete |

## Scope

**In scope**: the six files in the drift check.

**Out of scope**: `EnrichmentService.swift` (calls `thumbnails.store`, which keeps its signature); `AppModel.swift`; any change to what the views display.

## Git workflow

- Commit in the worktree; `perf:`-typed Conventional Commits. Do NOT push.

## Steps

### Step 1: Decoded-image cache in ThumbnailCache (test-first)

Convert `ThumbnailCache` to `public final class ThumbnailCache: @unchecked Sendable` (the NSCache it wraps is thread-safe; document that with a one-line comment). Add:

```swift
private let decoded = NSCache<NSUUID, NSImage>()

public func image(for id: UUID) -> NSImage? {
    if let cached = decoded.object(forKey: id as NSUUID) { return cached }
    guard let image = NSImage(contentsOf: fileURL(for: id)) else { return nil }
    decoded.setObject(image, forKey: id as NSUUID)
    return image
}
```

`NSImage` requires `import AppKit` in this file; AppKit is a system framework and this package is macOS-only, so that is fine. Invalidate in `store(_:for:)` (after a successful write, `decoded.removeObject(forKey:)` so a refreshed thumbnail is re-read) and in `remove(for:)`.

Tests first, in `ThumbnailCacheTests.swift` (follow the existing PNG-generation helper there): `imageForReturnsNilWithoutAFile`, `imageForReadsAndThenCaches` (store a valid image, call `image(for:)` twice, expect non-nil; then `remove(for:)` and expect `image(for:)` nil — proving invalidation), `storeInvalidatesTheDecodedCache` (store image A, read it, store image B for the same id, `image(for:)` must reflect B — compare pixel sizes of two differently-sized generated images).

**Verify**: `swift test --filter ThumbnailCacheTests` → all pass including 3 new.

### Step 2: Views read through the cache

Replace all four `NSImage(contentsOf: model.thumbnails.fileURL(for: ...))` call sites (grid card, list row badge, popover pick badge; search for `NSImage(contentsOf` to be sure you found every one) with `model.thumbnails.image(for: ...)`. Display logic unchanged.

**Verify**: `swift build` → Build complete; `grep -rn "NSImage(contentsOf" Sources/` → no matches.

### Step 3: One-pass counts in the store (test-first)

Add to `BookmarkStore`:

```swift
public struct Counts {
    public var byFolder: [String: Int]
    public var favorites: Int
    public var archived: Int
}

public func counts() -> Counts
```

One loop over `library.bookmarks`: a not-done bookmark increments `byFolder[its folder]`; `favoritedAt != nil` increments favorites (done or not, matching `favorites()`'s lens semantics — verify against the current `favorites()` filter before assuming; if `favorites()` includes done bookmarks, so must the count); `isDone` increments archived. Test: seed a store with a mix (filed, unsorted, done, favorited-and-done) and assert `counts()` equals the `.count` of the corresponding existing accessors for each bucket.

**Verify**: `swift test --filter BookmarkStoreTests` → all pass including the new test.

### Step 4: Views read counts()

In `LibraryWindow`'s sidebar: compute `let counts = model.store.counts()` once at the top of the `List` body (or as a computed property reading `model.revision` implicitly through `model.store`), and use `counts.favorites`, `counts.byFolder[folder] ?? 0`, `counts.archived` for the three badges. In `CapturePopover.countsLine`: build the parts from one `counts()` call instead of per-folder `bookmarks(in:)` scans, preserving the exact existing output copy (top three filed folders by count, the "N to sort." fallback, the singularization ponytail comment behavior).

**Verify**: `swift build` → Build complete. `swift test` full → all pass, zero warnings.

## Test plan

Covered in Steps 1 and 3; pattern files are the two existing test files.

## Done criteria

- [ ] `swift test` exits 0; the 4 new tests exist and pass.
- [ ] `grep -rn "NSImage(contentsOf" Sources/` → no matches.
- [ ] `grep -c "bookmarks(in: folder).count" Sources/Dogear/LibraryWindow.swift` → 0.
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- Excerpt mismatch (drift).
- Converting `ThumbnailCache` to a class breaks a consumer outside the in-scope list (report which; `EnrichmentService` holds it by `let` and should be unaffected).
- The counts test exposes a semantic mismatch between `favorites()` and your count (report the mismatch; do not silently pick one).

## Maintenance notes

- NSCache self-evicts under memory pressure; no size tuning is needed at 600px entries. If card size ever grows past ~300pt, revisit `maxPixelSize` first.
- Reviewer: confirm no view still holds `fileURL(for:)` for display purposes (drag/QR uses of the URL are fine and expected to remain).
