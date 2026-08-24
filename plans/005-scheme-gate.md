# Plan 005: Enforce the http(s) rule where URLs are written and where they are opened

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 960959c..HEAD -- Sources/DogearKit/URLCleaner.swift Sources/DogearKit/BookmarkStore.swift Sources/DogearKit/OpenGraphParser.swift Sources/DogearKit/TikTokFetcher.swift Sources/Dogear/CapturePopover.swift Sources/Dogear/LibraryWindow.swift Tests/DogearKitTests/BookmarkStoreTests.swift Tests/DogearKitTests/OpenGraphParserTests.swift`
> On any change since `960959c`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 001 (DONE), 004 (DONE)
- **Category**: security
- **Planned at**: commit `960959c`, 2026-08-24

## Why this matters

The design spec's invariant says only http and https URLs become bookmarks, and the app enforces it in exactly one place: `AppModel.capture(urls:)`. Two write paths bypass that gate: `EnrichmentService` writes the server-controlled post-redirect URL back through `BookmarkStore.update`, and `update`/`insert` themselves accept any scheme. Separately, page-controlled `og:image` and oEmbed `thumbnail_url` values become fetch targets with no scheme check (an incidental cast in the HTTP client is all that stops a `file:` image URL today). Finally, stored URLs are handed to `NSWorkspace.shared.open` at five call sites with no re-check, and `NSWorkspace` dispatches ANY scheme to whatever app claims it. None of these is currently exploitable end to end (URLSession restricts cross-scheme redirects), which is exactly why now is the cheap time to make the invariant structural instead of incidental.

## Current state

Relevant files and excerpts:

- `Sources/DogearKit/URLCleaner.swift`, has `firstHTTPURL`, `allHTTPURLs`, `canonicalString`. No single "is this a capturable URL" predicate.
- `Sources/DogearKit/BookmarkStore.swift:110-118`, `insert(url:)`:

```swift
private func insert(url: URL) -> (bookmark: Bookmark, isNew: Bool) {
    let canonical = URLCleaner.canonicalString(url)
    if let index = library.bookmarks.firstIndex(where: { $0.url == canonical }) {
```

- `Sources/DogearKit/BookmarkStore.swift:127`, `update(_:)` canonicalizes `bookmark.url` but performs no scheme check before storing.
- `Sources/DogearKit/OpenGraphParser.swift:50`, `imageURL: properties["og:image"].flatMap(URL.init(string:))`.
- `Sources/DogearKit/TikTokFetcher.swift:28`, `thumbnailURL: oembed.thumbnail_url.flatMap(URL.init(string:))`.
- `NSWorkspace.shared.open` call sites: `Sources/Dogear/CapturePopover.swift:208, 346` and `Sources/Dogear/LibraryWindow.swift:757, 908` open `bookmark.url`/`pick.url`; `LibraryWindow.swift:618` opens the constructed maps URL (fixed host, stays as is).

Conventions: no em dashes; Conventional Commits, no AI attribution; kit test-first; language mode v5 (`#/.../#` regexes only, none needed here).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter "BookmarkStoreTests\|OpenGraphParserTests\|TikTokFetcherTests"` | all pass |
| Full | `swift test` | exit 0, zero warnings |

## Scope

**In scope**: the eight files in the drift check (TikTokFetcherTests additions allowed under the OpenGraphParserTests bullet's intent; add tests where the change lives), plus `Tests/DogearKitTests/EnrichmentServiceTests.swift` for MECHANICAL updates only: its 12 `let (bookmark, isNew) = store.add(url: ...)` destructuring sites must adopt the optional return (force-unwrap `store.add(url: ...)!` is the accepted test idiom here; every such fixture uses an http URL, so the unwrap is safe by construction). No behavioral edits to that file.

**Out of scope**: `AppModel.capture(urls:)` (its filter stays; it gives the UI its early "invalid" signal); `EnrichmentService.swift` (its writes become safe because the store rejects; do not edit it); `HTTPClient.swift`; the maps `open` at `LibraryWindow.swift:618`.

## Git workflow

- Commit in the worktree; `fix(security):`-style Conventional Commits. Do NOT push.

## Steps

### Step 1: One predicate in the kit (test-first)

Add to `URLCleaner`:

```swift
/// The one rule for what may become or remain a bookmark URL.
public static func isCapturable(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "http" || scheme == "https"
}
```

Tests in `URLCleanerTests.swift` file are NOT in scope; instead test through the store in Step 2 (the predicate is trivial; its enforcement is what needs pinning). If you judge a direct predicate test worthwhile anyway, put it in `BookmarkStoreTests.swift`.

**Verify**: `swift build` → Build complete.

### Step 2: Enforce in the store (test-first)

- `insert(url:)`: first line, `guard URLCleaner.isCapturable(url) else { return? }`, the signature returns a non-optional tuple, so instead enforce one level up: in BOTH public entry points `add(url:)` and `add(urls:)`, filter/guard non-capturable input before reaching `insert`, with `add(url:)` returning early... STOP: `add(url:)` also returns a non-optional tuple. Resolution, and the shape to implement: make `insert(url:)` return an OPTIONAL tuple; `add(url:)` keeps its signature by treating a rejected URL as a no-op re-lookup, this is the one place a small signature change is acceptable: change `add(url:)` to return `(bookmark: Bookmark, isNew: Bool)?` and update its call sites. Search the app target for `store.add(url:` call sites and update them to handle nil by ignoring (the capture gate already filters, so nil is unreachable from the UI today; the change is defense in depth).
- `update(_:)`: after canonicalizing, `guard URL(string: bookmark.url).map(URLCleaner.isCapturable) == true else { return }`, a non-http scheme never replaces a stored URL; the pre-update record survives.

Tests in `BookmarkStoreTests.swift`:

1. `addRejectsNonHTTPSchemes`, `store.add(url: URL(string: "file:///etc/hosts")!)` returns nil and the library stays empty.
2. `updateRefusesToStoreANonHTTPURL`, add a normal bookmark, mutate its `url` to a `javascript:` string, call `update`, reload the record: the stored URL is unchanged (still the original http URL).

**Verify**: `swift test --filter BookmarkStoreTests` → all pass including 2 new.

### Step 3: Reject non-http image URLs at the parse boundary (test-first)

- `OpenGraphParser.swift:50`: wrap with the predicate: `properties["og:image"].flatMap(URL.init(string:)).flatMap { URLCleaner.isCapturable($0) ? $0 : nil }`.
- `TikTokFetcher.swift:28`: same treatment for `thumbnail_url`.

Tests: in `OpenGraphParserTests.swift`, `rejectsNonHTTPImageURL` (a page with `og:image` set to a `file:` URL yields `imageURL == nil`); in `TikTokFetcherTests.swift`, the analogous oEmbed case with a `file:` thumbnail_url string yields `thumbnailURL == nil` (follow that file's existing stub-response pattern).

**Verify**: `swift test --filter "OpenGraphParserTests|TikTokFetcherTests"` → all pass including 2 new.

### Step 4: Guard the open sites

Add one small helper in the app target (put it next to `copyToPasteboard` in `LibraryWindow.swift`, which is file-internal shared utility territory):

```swift
/// The one place a stored URL becomes a system open. Refuses anything that
/// is not http(s): NSWorkspace dispatches any scheme to whichever app
/// claims it, and stored data must not carry that authority.
func openBookmarkURL(_ string: String) {
    guard let url = URL(string: string), URLCleaner.isCapturable(url) else { return }
    NSWorkspace.shared.open(url)
}
```

Replace the four bookmark-open sites (`CapturePopover.swift:208, 346`; `LibraryWindow.swift:757, 908`) with `openBookmarkURL(...)`. The maps site at `LibraryWindow.swift:618` stays untouched.

**Verify**: `swift build` → Build complete; `grep -rn "NSWorkspace.shared.open" Sources/Dogear/ | wc -l` → 2 (the helper itself and the maps site). Full `swift test` → all pass, zero warnings.

## Test plan

Covered in Steps 2-3; pattern files are the named test files.

## Done criteria

- [ ] `swift test` exits 0; the 4 new tests exist and pass.
- [ ] `grep -n "isCapturable" Sources/DogearKit/URLCleaner.swift Sources/DogearKit/BookmarkStore.swift Sources/DogearKit/OpenGraphParser.swift Sources/DogearKit/TikTokFetcher.swift` → present in all four.
- [ ] `grep -rn "NSWorkspace.shared.open" Sources/Dogear/` → exactly 2 sites (helper + maps).
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- Excerpt mismatch (drift).
- A PRODUCTION call site of `add(url:)` genuinely needs the non-optional return (test-file destructuring churn is expected and in scope, not a stop).
- Any existing test asserts non-http URLs are storable (would mean a behavior contract exists that this plan contradicts; report it).

## Maintenance notes

- Plans 013/014 (importers) inherit safety automatically: anything feeding the store is now gated twice.
- Reviewer: confirm the nil-return from `add(url:)` cannot break the popover's "already saved" flow (rejected input was already impossible there thanks to the capture filter).
