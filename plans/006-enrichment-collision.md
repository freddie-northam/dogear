# Plan 006: Merge instead of delete on redirect collision, and close the duplicate race

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4bac044..HEAD -- Sources/DogearKit/EnrichmentService.swift Tests/DogearKitTests/EnrichmentServiceTests.swift`
> On any change since `4bac044`, compare the "Current state" excerpt against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: 001 (DONE), 005 (DONE)
- **Category**: bug
- **Planned at**: commit `4bac044`, 2026-08-24

## Why this matters

When enrichment resolves a bookmark's URL and finds another bookmark already holds it (a short link that expands to an existing save), the current code DELETES the bookmark being enriched and re-adds the survivor. That path is reachable long after capture via "Refresh Metadata", so refreshing an old, annotated, favourited bookmark that now redirects onto a duplicate silently discards its note, its star, its manually chosen folder, and its original save date, and orphans its cached thumbnail file. Separately, the collision check runs right after the metadata fetch but the URL is only persisted after two more suspension points (categorize, thumbnail download); with four enrichments running concurrently, two different short links resolving to the same target can both pass the check and both write the same canonical URL, creating duplicates that the store's dedupe can no longer collapse.

## Current state

- `Sources/DogearKit/EnrichmentService.swift` — `enrich(id:)`; the whole method is the surface. Current collision block (lines 32-39):

```swift
// Post-redirect dedupe: the resolved URL may match an existing bookmark.
if store.library.bookmarks.contains(where: { $0.url == resolved && $0.id != id }) {
    store.remove(id: id)
    // Re-add the survivor through add(): its re-add path clears doneAt and bumps the
    // bookmark to the top, so re-sharing a short link surfaces it like any re-add.
    store.add(url: result.resolvedURL)
    return
}
bookmark.url = resolved
```

The final write block (end of the method) already re-reads `latest` by id and merges enrichment fields onto it before `store.update(latest)`. Note `store.add(url:)` now returns an optional (plan 005); the bare call above compiles because it is `@discardableResult`.

- `Tests/DogearKitTests/EnrichmentServiceTests.swift` — has `redirectCollisionCollapsesDuplicate` and `redirectCollisionBumpsTheSurvivorToTheTop` pinning the current delete-and-readd behavior; they will need updating to the merge semantics. Also has an `InterceptingHTTPClient` (triggers a closure on the Nth `data(from:)` call) used by the mid-flight refile tests: reuse it for the race test. The `makeEnvironment(client:)` helper builds a store + service on a temp dir.
- `BookmarkStore` API you will use: `remove(id:)`, `update(_:)`, `add(url:)`, `library.bookmarks`; `ThumbnailCache.remove(for:)` via the service's `thumbnails` property.

Conventions: no em dashes; Conventional Commits, no AI attribution; kit test-first; `EnrichmentService` is `@MainActor` (keep it).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter EnrichmentServiceTests` | all pass |
| Full | `swift test` | exit 0, zero warnings |

## Scope

**In scope**: the two files in the drift check.

**Out of scope**: `BookmarkStore.swift` (no new store API; compose existing calls), `AppModel.swift` (the 4-wide concurrency stays), any UI file.

## Git workflow

- Commit in the worktree; `fix(enrichment):` Conventional Commit(s). Do NOT push.

## Steps

### Step 1: Move the collision check to the final write (test-first)

Write the race test first, in `EnrichmentServiceTests.swift`, modeled on the existing intercepting-client tests: two bookmarks A (`https://short.example/a`) and B (`https://short.example/b`) whose stub redirects BOTH resolve to the same `https://target.example/page`. Use `InterceptingHTTPClient` so that during A's thumbnail fetch (its second `data(from:)` call) the test runs `await service.enrich(id: B.id)` to completion. Then let A finish. Assert `store.library.bookmarks.filter { $0.url == "https://target.example/page" }.count == 1`. This test must FAIL on the current code (both survive as duplicates); confirm the failure before changing production code.

Then restructure `enrich(id:)`: delete the early collision block after the fetch; keep `bookmark.url = resolved`; perform the collision check INSIDE the final re-read block, immediately before `store.update(latest)`, with no suspension point between the check and the write.

**Verify**: `swift test --filter EnrichmentServiceTests` → the new race test passes; the two existing collision tests may now fail on semantics (expected; Step 2 fixes them).

### Step 2: Merge instead of delete (test-first)

Replace the delete-and-readd semantics with a merge into the survivor. Write these tests first (update the two existing collision tests to these names/semantics rather than keeping stale ones):

1. `redirectCollisionMergesIntoTheSurvivor` — existing bookmark S at the target URL (no note, not favourited); bookmark D (`note: "keep me"`, `favoritedAt` set, `manuallyFiled` folder "Recipes") whose URL redirects to S's URL. After `enrich(D.id)`: exactly one bookmark holds the target URL, it has id S (the survivor), `note == "keep me"`, `favoritedAt != nil`, folder "Recipes" with `manuallyFiled == true`, `createdAt == min(S.createdAt, D.createdAt)`, and `doneAt == nil`.
2. `redirectCollisionKeepsSurvivorFieldsWhenPresent` — S already has a note and a star; D has different ones; after merge S keeps ITS OWN note and star (merge fills gaps only).
3. `redirectCollisionBumpsTheSurvivorToTheTop` (keep the name) — the survivor is at index 0 after the merge.
4. `redirectCollisionRemovesTheDuplicateThumbnail` — D had a stored thumbnail (use the PNG helper from `ThumbnailCacheTests` or store any valid image via `service.thumbnails.store`); after merge `thumbnails.exists(for: D.id) == false`.

Implementation of the merge, in the final block where the collision is detected (`survivor` = the other bookmark with the same url):

- Fill gaps: `survivor.note = survivor.note ?? latest.note`; same for `favoritedAt`.
- Manual folder: if `latest.manuallyFiled && !survivor.manuallyFiled`, copy `folder` and set `manuallyFiled = true` on the survivor.
- `createdAt`: `Bookmark.createdAt` is a `let`; construct the merged survivor via the memberwise `Bookmark(...)` initializer with `createdAt: min(...)` and every other field from the survivor (after the gap-fill above).
- Clear `survivor.doneAt` (documented intent: a re-share resurfaces).
- Write: `store.remove(id: latest.id)` (the duplicate), `thumbnails.remove(for: latest.id)`, then `store.remove(id: survivor.id)` followed by re-inserting the merged survivor at the top: since the store has no insert-at-index API and `add(url:)` would lose fields, do this as `store.update(mergedSurvivor)` then `store.add(url: URL(string: mergedSurvivor.url)!)` — `add`'s re-add path finds the existing record by canonical url, clears doneAt, and bumps it to index 0 while preserving every other field. Verify by reading `insert(url:)` in `BookmarkStore` that it preserves fields on the re-add path (it removes and re-inserts the same `existing` record).

**Verify**: `swift test --filter EnrichmentServiceTests` → all pass including the 4 tests above and the race test. Then `swift test` full → all pass, zero warnings.

## Test plan

Covered in Steps 1-2; pattern: existing intercepting-client tests in the same file.

## Done criteria

- [ ] `swift test` exits 0; the race test and the 4 merge tests exist and pass.
- [ ] `grep -n "store.remove(id: id)" Sources/DogearKit/EnrichmentService.swift` → no match (the early delete block is gone).
- [ ] In `enrich(id:)`, no `await` appears between the collision check and `store.update` (read to confirm; cite line numbers in your report).
- [ ] `git status --porcelain` shows only the two in-scope files.

## STOP conditions

- Excerpt mismatch (drift).
- The race test cannot be made to fail on the current code after one honest attempt (report the interleaving you built; the fix may still be correct but the test would prove nothing).
- `insert(url:)`'s re-add path does NOT preserve fields (would break the bump approach; report and propose the store change as a follow-up rather than editing the store).

## Maintenance notes

- Plan 009 refactors the fetch path; it must keep the check-then-write adjacency established here.
- Reviewer: scrutinize the memberwise reconstruction for a dropped field (compare against the full `Bookmark` field list: id, url, title, author, note, folder, source, createdAt, doneAt, hasThumbnail, manuallyFiled, favoritedAt).
