# Plan 011: Investigate AppleScript threading and the stacked rename alert, then fix what is real

> **Executor instructions**: This is an INVESTIGATE plan: the first two steps
> produce findings, and only a confirmed finding proceeds to a fix step.
> Follow it step by step, run every verification, and STOP on the listed
> conditions. Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4bac044..HEAD -- Sources/Dogear/LibraryWindow.swift`
> On any change since `4bac044`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug (investigate)
- **Planned at**: commit `4bac044`, 2026-08-24

## Why this matters

Two MED/LOW-confidence findings need facts before fixes. (1) The Notes importer runs `NSAppleScript.executeAndReturnError` inside `Task.detached`, off the main thread. NSAppleScript is not documented as thread-safe, and Apple-event dispatch from a background thread has a history of hangs; a hang here would look like an endless "Reading your notes..." spinner with no cancel. (2) The rename-collision alert is set from inside the rename alert's own Save action; if SwiftUI processes the second presentation during the first alert's dismissal, the collision alert never appears and the user sees the rename silently fail. Both need verification, not assumption.

## Current state

- `Sources/Dogear/LibraryWindow.swift`:
  - line 349: `Task.detached {` followed by `let bodies = readNotesBodies()` and a hop back via `MainActor.run`.
  - line 410: `private func readNotesBodies() -> String?` builds a FIXED script string (`tell application "Notes" to get body of every note`) and calls `NSAppleScript(source:)?.executeAndReturnError(&errorInfo)`.
  - line 35: `@State private var renameCollided = false`; line 78: `.alert("Folder Name in Use", isPresented: $renameCollided)`; line 375: `saveRename()` runs from the Rename alert's Save button and sets `renameCollided = true` at line 386 when the store refused the rename.
  - The Notes sheet is `NotesImportSheet` with states `.confirm`, `.running`, `.finished(String)`.

Conventions: no em dashes; Conventional Commits, no AI attribution; UI untested (verification here is documented reasoning + a build).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | Build complete |
| Full | `swift test` | exit 0 |

## Scope

**In scope**: `Sources/Dogear/LibraryWindow.swift` only, and only the two areas above.

**Out of scope**: the AppleScript string itself; the importer's parsing; any kit file.

## Git workflow

- Commit in the worktree only if a fix step runs; `fix(library):` Conventional Commit. Do NOT push.

## Steps

### Step 1: Investigate NSAppleScript threading (no code change)

Consult Apple's "Thread Safety Summary" (Foundation section) and the `NSAppleScript` class reference. Record verbatim which category NSAppleScript falls under (thread-safe / not thread-safe / unlisted). Also note: `NSAppleScript` docs state instances must be used from the thread that created them? Determine the documented answer and cite it.

Decision rule:
- Documented NOT thread-safe or "main thread only": proceed to Step 3 (fix).
- Documented thread-safe: record it; skip Step 3.
- Unlisted/ambiguous: treat as not thread-safe (the conservative reading) and proceed to Step 3, noting the ambiguity.

**Verify**: your report contains the citation and the decision.

### Step 2: Investigate the stacked alert (reasoning + one focused check)

Read `saveRename()` and both alert modifiers. Trace the state sequence when Save is pressed in the Rename alert with a colliding name: the Rename alert's `isPresented` binding setter runs (`renamingFolder = nil`), the Save action runs `saveRename()`, which sets `renameCollided = true`. Determine whether `saveRename` reads `renamingFolder` AFTER the binding setter could have nil-ed it (if so, the rename is a silent no-op independent of the alert question). Cite line numbers.

Decision rule: if `saveRename` depends on `renamingFolder` being non-nil at action time and SwiftUI's alert dismissal can clear it first, that is a confirmed defect: proceed to Step 4. If `saveRename` captures the folder name before the alert dismissal can interfere, record it and skip Step 4 unless the stacked-presentation risk itself is independently confirmed by documentation.

**Verify**: your report contains the trace with line numbers and the decision.

### Step 3 (conditional): Run AppleScript on the main actor with a cancel path

Replace `Task.detached { ... }` with a main-actor execution: call `readNotesBodies()` directly (it blocks the main thread for the duration of the Apple event; the `.running` state already shows a spinner, and the sheet cannot be interacted with meanwhile, which is acceptable for a one-shot import). Add a `Cancel` button to the `.running` state that sets the state back to `.confirm`, since the call is synchronous on the main actor, cancel cannot interrupt an in-flight event; document that limitation in a one-line comment and keep the button (it lets the user dismiss a sheet whose event has already returned but whose result is still processing). If you judge main-actor blocking unacceptable, the alternative is a dedicated serial `Thread` with its own run loop that owns the `NSAppleScript`; prefer the simpler main-actor form for v1 and say why.

**Verify**: `swift build` → Build complete; `grep -n "Task.detached" Sources/Dogear/LibraryWindow.swift` → no match.

### Step 4 (conditional): Single-alert rename flow

Refactor the rename UI to one alert driven by one state enum (`enum RenameState { case idle, editing(folder: String), collided(folder: String) }`) so the collision message is presented by the SAME alert modifier with different content, never by a second alert triggered from the first's dismissal. Capture the folder name in the enum, not in a separate `@State` that a binding setter can clear.

**Verify**: `swift build` → Build complete; `grep -c "\.alert(" Sources/Dogear/LibraryWindow.swift` decreased by one compared to before your change (report both numbers).

### Step 5: Full suite

**Verify**: `swift test` → all pass, zero warnings.

## Test plan

No automated UI tests (spec). The deliverable is the investigation report plus any conditional fix, build-verified.

## Done criteria

- [ ] Report contains both investigation decisions with citations/line numbers.
- [ ] If Step 3 ran: no `Task.detached` remains in the file.
- [ ] If Step 4 ran: one fewer `.alert(` modifier, and the rename folder name lives in the state enum.
- [ ] `swift test` exits 0; `git status --porcelain` shows only `LibraryWindow.swift` (or nothing, if no fix was warranted).

## STOP conditions

- Excerpt mismatch (drift).
- Step 3's main-actor form produces a visibly frozen UI beyond the sheet in your own reasoning about the run loop (report; do not build the thread alternative without reviewer sign-off).

## Maintenance notes

- Plan 013 (Notes importer v2) multiplies AppleScript calls per run; whatever threading decision lands here is the foundation it builds on, so state it clearly in the report.
