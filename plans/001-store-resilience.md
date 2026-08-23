# Plan 001: Make the store recover from a missing library file and migrate old libraries forward

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat e64f9ca..HEAD -- Sources/DogearKit/BookmarkStore.swift Sources/DogearKit/Models.swift Sources/DogearKit/URLCleaner.swift Tests/DogearKitTests/BookmarkStoreTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `e64f9ca`, 2026-08-24

## Why this matters

Dogear stores the user's whole library in one JSON file with a `.bak` rotation. Three gaps undermine that safety story. First, a *missing* `library.json` with a healthy `library.json.bak` silently starts an empty library, and because `saveNow()` only rotates when the main file exists, the second save copies the new empty file over the good backup: total silent data loss. Second, when a new default folder ships (Music did, in commit `e64f9ca`), existing libraries never receive it, because `Library.defaultFolders` is only consulted for brand-new stores — so the Music keywords and streaming domain hints are dead code for every upgrading user. Third, when URL canonicalization rules improve (twitter.com now folds into x.com), already-stored URLs keep their old form forever, so an old save of a tweet never dedupes against a new save of the same tweet. All three are one shape of problem: the store has no forward-migration step at load time.

## Current state

Relevant files:

- `Sources/DogearKit/BookmarkStore.swift` — the store. Load logic in `init` (lines 12-37), save with backup rotation in `saveNow()` (lines 214-231).
- `Sources/DogearKit/Models.swift` — `Library` struct (lines 60-71), `Bookmark` struct above it. `Library` has only `folders` and `bookmarks`.
- `Sources/DogearKit/URLCleaner.swift` — `canonicalString(_ url: URL) -> String` is the canonical form used for dedupe. It is idempotent.
- `Tests/DogearKitTests/BookmarkStoreTests.swift` — store tests, including `recoversFromCorruptStoreUsingBackup` and `recoveryDoesNotClobberTheGoodBackup`. Uses a `tempDir()` helper at the top of the file, Swift Testing style (`@Test`, `#expect`).

`BookmarkStore.init` today (`Sources/DogearKit/BookmarkStore.swift:12-37`):

```swift
public init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("library.json")
    backupURL = directory.appendingPathComponent("library.json.bak")

    if let data = try? Data(contentsOf: fileURL),
       let loaded = try? JSONDecoder().decode(Library.self, from: data) {
        library = loaded
    } else if FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: backupURL),
              let loaded = try? JSONDecoder().decode(Library.self, from: data) {
        // The main file exists but is unreadable: restore from backup, never start empty.
        // Write directly (no rotation): library.json is corrupt, not a known-good state,
        // so it must never be copied over the good .bak.
        library = loaded
        didRecoverFromBackup = true
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: fileURL, options: .atomic)
        }
    } else if FileManager.default.fileExists(atPath: fileURL.path) {
        throw CocoaError(.fileReadCorruptFile)
    } else {
        library = Library(folders: Library.defaultFolders, bookmarks: [])
    }
}
```

Note the second branch is gated on `FileManager.default.fileExists(atPath: fileURL.path)` — a missing main file skips the backup entirely and falls to the fresh-library branch.

`Library` today (`Sources/DogearKit/Models.swift:60-71`):

```swift
public struct Library: Codable, Equatable, Sendable {
    public var folders: [String]
    public var bookmarks: [Bookmark]

    public static let defaultFolders = ["Recipes", "Restaurants", "Shows", "Music", "Articles", "Unsorted"]
    public static let unsorted = "Unsorted"

    public init(folders: [String], bookmarks: [Bookmark]) {
        self.folders = folders
        self.bookmarks = bookmarks
    }
}
```

Repo conventions that apply:

- New `Library`/`Bookmark` stored fields MUST be optional (`Int?`, `Date?`) so libraries written before the field decode with the synthesized `Decodable` (missing key becomes nil). This rule is documented in `CONTRIBUTING.md` under "Extension points"; `Bookmark.favoritedAt` is the exemplar.
- Comments state constraints, not narration. No em dashes anywhere (code, comments, commit messages). ASD-STE100 style for any doc text.
- Conventional Commits, imperative capitalized subject, body explains why. No AI attribution of any kind.
- Deliberate shortcuts with a known ceiling get a `// ponytail: <ceiling>, <upgrade path>` comment.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Full tests | `swift test` | exit 0, "Test run with N tests passed", zero warnings |
| Focused tests | `swift test --filter BookmarkStoreTests` | all pass |
| Build | `swift build` | "Build complete!" |

## Scope

**In scope** (the only files you should modify):

- `Sources/DogearKit/BookmarkStore.swift`
- `Sources/DogearKit/Models.swift`
- `Tests/DogearKitTests/BookmarkStoreTests.swift`

**Out of scope** (do NOT touch, even though they look related):

- `Sources/DogearKit/URLCleaner.swift` — you call it; you do not change it.
- `Sources/Dogear/` (the app target) — `AppModel` already surfaces `didRecoverFromBackup`; no UI change is needed.
- `Sources/DogearKit/EnrichmentService.swift` — its dedupe behavior is another plan.

## Git workflow

- Branch: you are already on an isolated worktree branch; commit there.
- One commit per step or one combined `fix(store):` commit at the end; Conventional Commits, imperative capitalized subject, body says why. Example from `git log`: `fix(store): Harden folder mutations and report encode failures`.
- Do NOT push.

## Steps

### Step 1: Recover from the backup when the main file is missing

In `BookmarkStore.init`, restructure the load so the backup is tried whenever the main file fails to load, whether it is corrupt or missing:

- Branch 1 (unchanged): main file reads and decodes.
- Branch 2 (changed): `Data(contentsOf: backupURL)` decodes. Remove the `fileExists(atPath: fileURL.path)` gate. Set `didRecoverFromBackup = true` and write the recovered library directly to `fileURL` exactly as the current branch does (no rotation).
- Branch 3 (unchanged semantics): the main file EXISTS but neither it nor the backup decoded: `throw CocoaError(.fileReadCorruptFile)`. Keep this crash-over-silent-loss behavior.
- Branch 4 (unchanged): neither file exists: fresh `Library(folders: Library.defaultFolders, bookmarks: [])`.

**Verify**: `swift test --filter BookmarkStoreTests` → all existing tests still pass (the corrupt-recovery tests pin branches 2 and 3).

### Step 2: Add a schema version field to Library

Add `public var schemaVersion: Int?` to `Library` (after `bookmarks`), include it in `init` with a default of `nil` so existing call sites compile unchanged: `public init(folders: [String], bookmarks: [Bookmark], schemaVersion: Int? = nil)`. Add a static `public static let currentSchemaVersion = 2` on `Library`. Optional type is mandatory (see conventions): old files must decode.

**Verify**: `swift build` → Build complete, zero warnings.

### Step 3: Migrate loaded libraries forward in init

After a successful load (branches 1 and 2 of Step 1), run a private `migrate()` method when `library.schemaVersion ?? 1 < Library.currentSchemaVersion`:

1. **Folder adoption**: for each folder in `Library.defaultFolders` (except `Library.unsorted`) missing from `library.folders`, insert it before `Library.unsorted` (use `firstIndex(of: Library.unsorted) ?? endIndex`, matching `addFolder`'s pattern). The schema-version gate is what makes this a one-shot: a user who later deletes Music is not fighting the app every launch.
2. **URL re-canonicalization**: for each bookmark, if `URL(string: bookmark.url)` parses and `URLCleaner.canonicalString` of it differs from the stored string, update the stored `url`. When the new canonical form collides with an EARLIER bookmark's url in the same pass, drop the later duplicate, but first copy onto the survivor any `note` or `favoritedAt` the dropped one has and the survivor lacks, and keep the survivor's other fields.
3. Set `library.schemaVersion = Library.currentSchemaVersion` and persist ONCE via a direct atomic write to `fileURL` (same pattern as the recovery write in init; do not call `saveNow()`, which would rotate a pre-migration file into `.bak` — that rotation is fine, actually desirable, so prefer `saveNow()` here ONLY if the main file exists; when it does not (fresh recovery from backup), the direct write is correct. Simplest correct rule: call `saveNow()` when the migration changed anything).

Wire the fresh-library branch (branch 4) to set `schemaVersion: Library.currentSchemaVersion` at construction so new stores never run the migration.

**Verify**: `swift build` → Build complete.

### Step 4: Tests

Add to `Tests/DogearKitTests/BookmarkStoreTests.swift`, modeled on `recoversFromCorruptStoreUsingBackup`:

1. `recoversFromBackupWhenMainFileIsMissing` — create a store, add 2 bookmarks (produces a `.bak` holding 1), delete `library.json` only, reload: `#expect(store.library.bookmarks.count == 1)` and `#expect(store.didRecoverFromBackup)`.
2. `missingMainFileRecoveryDoesNotDestroyTheBackup` — same setup; after reload, corrupt `library.json` again and reload a second time; the second recovery must still find bookmarks (proves the good `.bak` survived the first recovery cycle, including the post-recovery saves: after reload one, call `store.add(url:)` twice and assert the `.bak` still decodes to a non-empty library via a third reload).
3. `oldLibraryGainsNewDefaultFolders` — write a `library.json` by hand (JSON literal string) with folders `["Recipes","Restaurants","Shows","Articles","Unsorted"]`, no `schemaVersion` key, one bookmark; load; `#expect(store.library.folders.contains("Music"))`, Music appears before Unsorted, and `#expect(store.library.schemaVersion == Library.currentSchemaVersion)`.
4. `folderAdoptionRunsOnce` — after test 3's load, remove Music via `store.removeFolder("Music")`, reload; `#expect(!store.library.folders.contains("Music"))` (the migration did not resurrect it).
5. `oldURLsAreRecanonicalizedOnLoad` — hand-written library with two bookmarks: `https://twitter.com/jack/status/20` (with `"note": "keep me"`) and `https://x.com/jack/status/20` (no note), no `schemaVersion`; load; `#expect(store.library.bookmarks.count == 1)`, the survivor's url is the x.com canonical form, and `#expect(store.library.bookmarks[0].note == "keep me")`.

For the hand-written JSON, mirror the field names of the current `Bookmark` Codable output; the existing `decodesALibraryWrittenBeforeFavorites` test in this file shows the pattern for raw-JSON fixtures — follow it, including the date encoding it uses.

**Verify**: `swift test` → all pass including the 5 new tests, zero warnings.

## Test plan

Covered by Step 4. Pattern files: `recoversFromCorruptStoreUsingBackup` and `decodesALibraryWrittenBeforeFavorites` in the same test file.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift test` exits 0; the 5 new tests named in Step 4 exist and pass.
- [ ] `swift build` exits 0 with zero warnings.
- [ ] `grep -n "fileExists" Sources/DogearKit/BookmarkStore.swift` shows no existence gate between the main-file load and the backup attempt in `init` (the throw branch may still check existence).
- [ ] `grep -n "schemaVersion" Sources/DogearKit/Models.swift` shows an optional `Int?` stored property.
- [ ] `git status --porcelain` in the worktree shows only in-scope files modified.

## STOP conditions

Stop and report back (do not improvise) if:

- The `BookmarkStore.init` in the live code does not match the excerpt above (drift).
- `decodesALibraryWrittenBeforeFavorites` does not exist in the test file (your raw-JSON pattern is gone; the fixture approach needs rethinking).
- Making `schemaVersion` optional still fails decoding of the hand-written fixtures (would mean the Codable synthesis assumption is wrong).
- Any existing test breaks and the fix would require changing files out of scope.

## Maintenance notes

- Every future canonicalization rule change is now automatically applied to old libraries at load; bump `currentSchemaVersion` when adding a migration that must re-run.
- Every future default-folder addition is delivered by the same migration; the folder-identity test planned in 008 will assert the lockstep sites.
- Reviewer should scrutinize the collision-merge rule in Step 3.2 (survivor keeps its fields; note/favorite copied only when the survivor lacks them) and that `saveNow()` is called at most once per migration.
