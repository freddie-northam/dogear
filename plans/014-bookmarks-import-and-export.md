# Plan 014: Import browser bookmark files and export the library to a file

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`. Commit as soon as the full suite
> is green, BEFORE writing your final report.
>
> **Drift check (run first)**: `git diff --stat 9871687..HEAD -- Sources/DogearKit/URLCleaner.swift Sources/DogearKit/Models.swift Sources/Dogear/LibraryWindow.swift Tests/DogearKitTests/URLCleanerTests.swift`
> `LibraryWindow.swift` may have changed under plan 011 (rename-alert and
> Notes-import threading areas only); a diff confined to those areas is not a
> stop. Compare the "Current state" excerpts for the areas THIS plan touches;
> on a mismatch there, STOP.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 003 (DONE), 005 (DONE)
- **Category**: direction
- **Planned at**: commit `9871687`, 2026-08-24

## Why this matters

Dogear has exactly one bulk import source (Apple Notes) and one export (markdown to the pasteboard). Users arriving with an existing bookmark pile in Safari, Chrome, or Firefox have to hand-shuttle it, and anyone who wants their data out gets a clipboard string. Both directions are disproportionately cheap: every browser exports the same Netscape bookmark HTML format, `URLCleaner.allHTTPURLs(inHTML:)` already extracts links from HTML, `AppModel.capture(urls:)` is the single gated ingestion path, and `Bookmark.markdownList` already renders a safe export. This plan closes the asymmetry with no permission prompts (a file the user chooses via the open panel needs none).

## Current state

- `Sources/DogearKit/URLCleaner.swift:48-50`:

```swift
public static func allHTTPURLs(inHTML html: String) -> [URL] {
    allHTTPURLs(in: html.replacingOccurrences(of: "&amp;", with: "&"))
}
```

This is what the Notes importer uses. Netscape bookmark files are HTML with `<A HREF="...">Title</A>` entries; the same function extracts their hrefs. Titles are NOT captured today (enrichment fetches them later); that is acceptable for v1 of this feature and keeps the plan small.

- `Sources/DogearKit/Models.swift`: `Bookmark.markdownLink` (angle-bracket URL form) and `static func markdownList(_:) -> String`.
- `Sources/Dogear/LibraryWindow.swift`: the toolbar `plus` Menu at ~line 203-215 contains `Label("Save from Clipboard", systemImage: "doc.on.clipboard")` and `Label("Import from Notes...", systemImage: "square.and.arrow.down")`; the sidebar folder context menu at ~line 142 has `Label("Copy as Markdown List", systemImage: "doc.on.doc")` calling `copyToPasteboard(Bookmark.markdownList(model.store.bookmarks(in: folder)))`. The `NotesImportSheet` shows the feedback idiom (`.finished(String)` state → message + Done).
- `AppModel.capture(urls:) -> CaptureResult` with `new` and `total` counts (the scheme gate lives there and in the store since plan 005).

Conventions: zero third-party deps; `NSOpenPanel`/`NSSavePanel` are AppKit, fine; no em dashes; Conventional Commits, no AI attribution; kit logic test-first; STE copy; UI untested (build-verified).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter URLCleanerTests` | all pass |
| Full | `swift test` | exit 0, zero warnings |
| Build | `swift build` | Build complete |

## Scope

**In scope**: the four files in the drift check.

**Out of scope**: `AppModel.swift`; the Notes importer; the README (publication plan covers docs); any change to `markdownList`'s format.

## Git workflow

- Commit in the worktree; `feat:` Conventional Commits. Do NOT push.

## Steps

### Step 1: Bookmark-file link extraction (test-first)

Netscape files escape `&` as `&amp;` in hrefs exactly like Notes HTML, so `allHTTPURLs(inHTML:)` already handles them. Write the test first in `URLCleanerTests.swift`: `extractsLinksFromANetscapeBookmarkFile` using an inline fixture string shaped like a real export:

```html
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<TITLE>Bookmarks</TITLE>
<DL><p>
    <DT><H3>Reading</H3>
    <DL><p>
        <DT><A HREF="https://a.com/one?x=1&amp;y=2" ADD_DATE="1700000000">One</A>
        <DT><A HREF="https://b.com/two">Two</A>
    </DL><p>
</DL><p>
```

Assert two URLs, in order, and that the first has query `x=1&y=2` (ampersand unescaped). If this passes with no production change, good: the test documents the contract and Step 1 has no code change. If it fails, fix `allHTTPURLs(inHTML:)` minimally and report why.

**Verify**: `swift test --filter URLCleanerTests` → all pass including the new test.

### Step 2: Import from a bookmarks file (UI)

Add `Label("Import Bookmarks File...", systemImage: "doc.badge.plus")` to the toolbar `plus` Menu after the Notes item. Action: present an `NSOpenPanel` (allowed content types: `.html`; `canChooseDirectories = false`; `allowsMultipleSelection = false`), read the chosen file as UTF-8 (fall back to `String(decoding:as:)` on failure), run `URLCleaner.allHTTPURLs(inHTML:)`, and pass the result to `model.capture(urls:)`. Surface the result with the same alert idiom the file already uses (plan 002 added a `fileForMeResult`-style alert; add a sibling `@State private var importFileResult: String?`): copy, STE, no em dash:

- new > 0: `"Imported N links."` (singular `"Imported 1 link."`)
- total > 0 and new == 0: `"All N were already saved."`
- total == 0: `"No links found in that file."`

**Verify**: `swift build` → Build complete.

### Step 3: Export the library to a file (UI)

Add an `Export Library...` item to the same toolbar Menu (`Label("Export Library...", systemImage: "square.and.arrow.up")`), after a `Divider()`. Action: present an `NSSavePanel` (`nameFieldStringValue = "Dogear.md"`, allowed content type: a plain-text/markdown type via `UTType(filenameExtension: "md") ?? .plainText`), and write `Bookmark.markdownList(...)` of every not-done bookmark grouped by folder: a `## <Folder>` heading per non-empty folder followed by that folder's list, folders in `library.folders` order, then an `## Archive` section for done bookmarks if any. Build the string with a small private helper in `LibraryWindow.swift` (`exportMarkdown(_ library: Library) -> String`). Write with `String.write(to:atomically:encoding:)`; on failure set the shared storage-error text (`model.storageError`) so the existing alert reports it.

**Verify**: `swift build` → Build complete. `swift test` full → all pass, zero warnings.

## Test plan

Kit: Step 1's extraction test. The export string builder lives in the app target per the plan's scope; if you judge a kit-level `Library.markdownExport()` cleaner AND it needs no new kit file beyond `Models.swift`, you may put it there with one test asserting the heading/section structure (folder order, Archive last, empty folders skipped). Prefer that placement if it costs nothing extra.

## Done criteria

- [ ] `swift test` exits 0; the Netscape extraction test exists and passes.
- [ ] `grep -n "Import Bookmarks File...\|Export Library..." Sources/Dogear/LibraryWindow.swift` → both present.
- [ ] `grep -n "NSOpenPanel\|NSSavePanel" Sources/Dogear/LibraryWindow.swift` → both present.
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- Excerpt mismatch in the areas this plan touches (drift).
- `allHTTPURLs(inHTML:)` needs more than a one-line change to pass Step 1 (report the failing case).
- `NSOpenPanel`/`NSSavePanel` presentation from a SwiftUI toolbar action does not compile against the current target after one attempt (report the error).

## Maintenance notes

- Titles from the bookmark file are discarded; a follow-up could parse `<A ...>Title</A>` pairs into pre-filled titles so enrichment has a fallback for pages that no longer resolve.
- Safari Reading List import is deliberately excluded (needs Full Disk Access, a heavier permission ask).
- Reviewer: check that a file with zero links yields the "No links found" message, not the "already saved" one.
