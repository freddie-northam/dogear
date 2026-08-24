# Plan 013: Notes importer v2, in three shippable slices

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`. Commit after EACH slice as soon
> as the suite is green; each slice is independently shippable.
>
> **Drift check (run first)**: `git diff --stat a102d93..HEAD -- Sources/Dogear/LibraryWindow.swift Sources/DogearKit/ Tests/DogearKitTests/`
> `LibraryWindow.swift` and kit files may have changed under plans 009/014
> (fetch path; import/export menu items). Compare the "Current state"
> anchors for the Notes-import areas specifically; on a mismatch there,
> STOP. A diff confined to other areas is not a stop.

## Status

- **Priority**: P3
- **Effort**: M (three S slices)
- **Risk**: MED (AppleScript against Notes is permission-gated and hard to test)
- **Depends on**: 011 (DONE: AppleScript now runs on the main actor)
- **Category**: direction
- **Planned at**: commit `a102d93`, 2026-08-24

## Why this matters

A design spike found a real bug first: re-running the importer today calls `capture(urls:)` for every link found, and the store's re-add path clears `doneAt` and bumps to the top, so every archived bookmark that also lives in a note gets silently un-archived and pushed to the top of the library on a second import. Beyond that bug, the importer reads every note in every account on every run (the `// ponytail:` comment on `runNotesImport` names exactly this ceiling), which makes the app's one bulk-onboarding path slow to repeat and impossible to scope. The spike's recommended design, adopted here: (1) filter already-saved URLs before capture; (2) a two-step sheet that asks consent BEFORE the first Apple event and then lets the user tick folders; (3) per-folder incremental cursors in UserDefaults keyed by Notes folder id, so a newly ticked folder gets a full read and an already-imported one reads only notes modified since. No data-model change: cursors are per-Mac device state, not library content (CONTRIBUTING's sync-friendly storage rule is satisfied vacuously).

## Current state

- `Sources/Dogear/LibraryWindow.swift`:
  - lines 4-8: `enum NotesImportState: Equatable { case confirm, running, finished(String) }`
  - line 45: `@State private var importState: NotesImportState = .confirm`
  - line 376: `private func runNotesImport()` (sets `.running`, calls `readNotesBodies()` synchronously on the main actor since plan 011, then `finishImport(with:)`)
  - line 387: `private func finishImport(with bodies: String?)`, nil → the permission-denied message; otherwise `model.capture(urls: URLCleaner.allHTTPURLs(inHTML: bodies))` and a message from `result.total`/`result.new`.
  - line 451: `private func readNotesBodies() -> String?` with the fixed script `tell application "Notes" to get body of every note`, walking the returned list descriptor (1-indexed `atIndex`).
  - `NotesImportSheet` (line ~465) renders the three states with Cancel/Import, a spinner (plus Cancel since plan 011), and Done.
- `AppModel.capture(urls:) -> CaptureResult` (`new`, `total`).
- `BookmarkStore.library.bookmarks[].url` holds canonical URLs; `URLCleaner.canonicalString` is the dedupe key.
- `@AppStorage` is used throughout the app target for per-Mac settings (e.g. `"detectCopiedLinks"`, `"libraryView"`).
- Verified facts from Apple's Notes scripting dictionary (`/System/Applications/Notes.app/Contents/Resources/Notes.sdef`): `folder` has `name`, read-only `id`, and `note` elements; `note` has `body`, read-only `modification date` (an AppleScript date), and `password protected` (boolean). `every folder` at application level returns a flat list across accounts and nesting.

Conventions: kit logic test-first (the cursor/filter logic goes in DogearKit); no em dashes; Conventional Commits, no AI attribution; STE copy; UI untested (build-verified); the AppleScript source stays a fixed string with ONLY a folder id and an integer second-count interpolated (escape `"` and `\` in the id before interpolating; it is a string crossing into an interpreter).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter NotesImportPlanningTests` | all pass |
| Full | `swift test` | exit 0, zero warnings |
| Build | `swift build` | Build complete |

## Scope

**In scope**: `Sources/Dogear/LibraryWindow.swift` (Notes-import areas only), create `Sources/DogearKit/NotesImportPlanning.swift`, create `Tests/DogearKitTests/NotesImportPlanningTests.swift`.

**Out of scope**: `AppModel.swift`, `BookmarkStore.swift` (no new store API), any threading change to how AppleScript runs (plan 011's main-actor decision stands; multiplying calls multiplies main-thread blocking time, accepted for a one-shot import), caching folder names (fetch fresh each run; TCC grants persist).

## Git workflow

- One commit per slice: `fix(import):` for slice 1, `feat(import):` for slices 2 and 3. Do NOT push.

## Steps

### Slice 1: Never un-archive on re-import (test-first)

Kit: create `NotesImportPlanning.swift` with

```swift
public enum NotesImportPlanning {
    /// Links not already in the library, by canonical URL, in input order.
    public static func freshURLs(_ found: [URL], existing: Set<String>) -> [URL]
}
```

Test-first in `NotesImportPlanningTests.swift`: two found URLs of which one (in a differently-cased host / trailing-slash form) is already present canonically → one fresh URL returned, order preserved.

App: in `finishImport(with:)`, compute `existing = Set(model.store.library.bookmarks.map(\.url))`, `let found = URLCleaner.allHTTPURLs(inHTML: bodies)`, `let fresh = NotesImportPlanning.freshURLs(found, existing: existing)`, and capture only `fresh`. Messages, STE, no em dash: `found.isEmpty` → "No links found in your notes."; `fresh.isEmpty` → "All N links were already saved." (singular for 1); otherwise "Imported X links. Y were already saved." (omit the second sentence when Y is 0; singularize both).

**Verify**: `swift test --filter NotesImportPlanningTests` → pass; `swift build` → Build complete. Commit.

### Slice 2: Consent first, then choose folders

- Add `case choosing([NotesFolder])` to `NotesImportState` with `struct NotesFolder: Identifiable, Equatable { let id: String; let name: String }` (app target).
- Rename the first sheet button from Import to Continue; on Continue run a new `readNotesFolders() -> [NotesFolder]?` with the fixed script `tell application "Notes" to get {id of every folder, name of every folder}` (two parallel lists; walk both descriptors; zip). nil → the existing permission message via `.finished`. Otherwise `.choosing(folders)`.
- The `.choosing` view: title "Which folders?", a scrollable checkbox list (`Toggle` per folder), "Select all" / "Select none" plain buttons, Cancel, and Import (prominent; disabled when nothing is ticked). Persist the ticked set of folder ids in `@AppStorage("notesImportSelection")` as a JSON-encoded `[String]` so the sheet reopens with the same boxes ticked; default to all ticked on first run.
- `runNotesImport()` now iterates the ticked folders and reads each with a per-folder script: `tell application "Notes"\nset f to first folder whose id is "<ID>"\nget body of every note of f whose password protected is false\nend tell`. Concatenate bodies across folders; update the `.running` label per folder ("Reading <name>...") between calls (state is on the main actor; the spinner may or may not repaint between synchronous calls, accepted). A folder whose script errors is skipped and counted; the summary appends "Dogear could not read N folders." when N > 0.

**Verify**: `swift build` → Build complete. `swift test` → all pass. Commit.

### Slice 3: Incremental per-folder cursors (test-first)

Kit, in `NotesImportPlanning.swift`:

```swift
/// Per-folder cursors: a folder with no entry gets a full read; an entry means
/// read only notes modified after it. Keyed by the Notes folder id.
public struct NotesImportCursors: Codable, Equatable {
    public var lastImport: [String: Date]
    public init(lastImport: [String: Date] = [:])
    /// Seconds to subtract from "now" in the AppleScript, or nil for a full read.
    /// Includes a 60 second skew margin.
    public func secondsSince(folderID: String, now: Date) -> Int?
    public mutating func record(folderID: String, at: Date)
    public mutating func prune(keeping folderIDs: Set<String>)
}
```

Tests first: no entry → nil; entry 1 hour ago → 3660 (3600 + 60 margin); `record` then `secondsSince` → 60; `prune` drops ids not in the set.

App: store the cursors JSON-encoded in `@AppStorage("notesImportCursors")` (default `{}`). For each ticked folder, if `secondsSince` is non-nil, append ` and modification date > cutoff` to the whose-clause with `set cutoff to (current date) - <SECONDS>` interpolated as a single integer (locale-free). Record the folder's cursor ONLY after its read succeeded (a failed folder keeps its old cursor and is re-read next time). Prune cursors against the current folder id list on each run.

**Verify**: `swift test --filter NotesImportPlanningTests` → all pass (7+ tests); `swift build` → Build complete; full `swift test` → all pass, zero warnings. Commit.

## Test plan

Kit logic (fresh-URL filter, cursor selection, pruning) is fully unit-tested. AppleScript strings and the sheet are build-verified; manual QA: run the import twice against a real Notes library and confirm the second run reports links as already saved without touching the Archive.

## Done criteria

- [ ] `swift test` exits 0; `NotesImportPlanningTests` has at least 7 passing tests.
- [ ] `grep -n "freshURLs" Sources/Dogear/LibraryWindow.swift` → present in `finishImport`.
- [ ] `grep -n "case choosing" Sources/Dogear/LibraryWindow.swift` → present; `grep -c "tell application \\\\\"Notes\\\\\"" Sources/Dogear/LibraryWindow.swift` ≥ 2 (folder list script and per-folder body script).
- [ ] `grep -n "notesImportCursors" Sources/Dogear/LibraryWindow.swift` → present.
- [ ] Three commits, one per slice; `git status --porcelain` shows only in-scope files.

## STOP conditions

- Anchor mismatch in the Notes-import areas (drift).
- The two-list `{id of every folder, name of every folder}` descriptor cannot be walked with the existing `atIndex` approach after one attempt (report the descriptor shape you observed; you may reason from the sdef but MUST NOT run osascript from the shell, which would prompt the terminal for Automation access).
- Slice 1's message arithmetic conflicts with an existing test in the app target (there are none; if one appears, report).

## Maintenance notes

- Open questions the spike could not settle without a live Notes library (record answers in ROADMAP when known): whether `body` on a password-protected note errors (the filter excludes them either way); whether moving a note between folders bumps its modification date (if not, a "re-read everything" checkbox is the escape hatch); whether "Recently Deleted" appears in `every folder`.
- Reviewer: check the AppleScript interpolation escapes `"` and `\` in folder ids, and that no other value is interpolated.
