# Plan 008: Move folder styling into the kit and add the test that catches lockstep misses

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 2b471d7..HEAD -- Sources/Dogear/FolderColor.swift Sources/DogearKit/Categorizer.swift Tests/DogearKitTests/Fixtures/accuracy-set.json Tests/DogearKitTests/KeywordCategorizerTests.swift`
> On any change since `2b471d7`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `2b471d7`, 2026-08-24

## Why this matters

A folder's identity is spread over four hand-edited sites that must move in lockstep: `Library.defaultFolders`, the keyword table, the domain hints, and the color/symbol switches. The failure mode is demonstrated, not hypothetical: when Music was added (commit `e64f9ca`), the accuracy fixture was missed, so the app's headline auto-filing benchmark cannot detect a Music regression at all. There are also two provably shadowed duplicate domain-hint entries and an ordering comment the array does not honor. This plan does not build a registry; it moves the two app-side switches into the kit (they are pure `String -> Color/String`) and adds ONE test that fails whenever any future folder misses any of the sites, plus fixture entries so Music is actually benchmarked.

## Current state

Relevant files:

- `Sources/Dogear/FolderColor.swift` — 29 lines, two global functions (full current content below). SwiftUI `Color` is available in DogearKit (SwiftUI is a system framework; the kit already links Foundation/ImageIO; adding `import SwiftUI` to one kit file is fine and keeps the zero-third-party rule intact).

```swift
import SwiftUI

/// Reminders-style folder accents, defined once for the sidebar, the cards,
/// and the popover pick row. System colors only, so both appearances adapt.
func folderColor(for name: String) -> Color {
    switch name {
    case "Recipes": .orange
    case "Restaurants": .pink
    case "Shows": .purple
    case "Music": .red
    case "Articles": .blue
    case "Unsorted": .gray
    default: .teal
    }
}

/// The SF Symbol for a folder, shared by the sidebar and the popover badge.
func folderSymbol(for name: String) -> String {
    switch name {
    case "Recipes": "fork.knife"
    case "Restaurants": "mappin.and.ellipse"
    case "Shows": "tv"
    case "Music": "music.note"
    case "Articles": "doc.text"
    case "Unsorted": "tray"
    default: "folder"
    }
}
```

- `Sources/DogearKit/Categorizer.swift` — `keywords: [String: [String]]` table keyed by folder name (has entries for Recipes, Restaurants, Shows, Music, Articles); `domainHints: [(domain: String, folder: String)]` array whose comment claims longest-domain-first ordering. The array currently contains DUPLICATE entries: `("maps.google.com", "Restaurants")` and `("maps.apple.com", "Restaurants")` appear at BOTH line ~33 and line ~39; the second occurrences are unreachable (first match wins). It also contains `("github.com", "Code")` and `("gitlab.com", "Code")` where "Code" is deliberately NOT a default folder (opt-in by creating a folder named Code; a test covers it).
- `Tests/DogearKitTests/Fixtures/accuracy-set.json` — 40 entries, 10 each for Recipes/Restaurants/Shows/Articles; ZERO Music entries.
- `Tests/DogearKitTests/KeywordCategorizerTests.swift` — `meetsSeventyPercentAccuracyOnFixtureSet` decodes the fixture, runs `KeywordCategorizer` with `Library.defaultFolders`, asserts `entries.count == 40` and accuracy >= 0.7.

Conventions: no em dashes; Conventional Commits, no AI attribution; kit test-first; fixture entries are realistic titles/descriptions/urls with an `expected` folder (open the file and match its exact JSON shape).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter KeywordCategorizerTests` | all pass |
| Full | `swift test` | exit 0, zero warnings |

## Scope

**In scope**:

- Create: `Sources/DogearKit/FolderStyle.swift` (the two functions move here, `public`)
- Delete: `Sources/Dogear/FolderColor.swift`
- `Sources/DogearKit/Categorizer.swift` (duplicates + ordering + comment only; keyword/hint CONTENT otherwise unchanged)
- `Tests/DogearKitTests/Fixtures/accuracy-set.json` (add Music entries)
- `Tests/DogearKitTests/KeywordCategorizerTests.swift` (fixture-count assertion, new lockstep test)

**Out of scope**: every call site of `folderColor`/`folderSymbol` in `Sources/Dogear/` — the functions keep their names and signatures, and the app target already imports DogearKit in those files, so call sites must compile UNCHANGED. If any call site needs an edit beyond nothing, STOP. `Library.defaultFolders` itself. The "Code" hint entries (they stay, with their comment).

## Git workflow

- Commit in the worktree; `refactor(kit):` / `test:` Conventional Commits. Do NOT push.

## Steps

### Step 1: Move the style functions to the kit

Create `Sources/DogearKit/FolderStyle.swift` with the two functions verbatim, marked `public`, keeping both doc comments. Delete `Sources/Dogear/FolderColor.swift`.

**Verify**: `swift build` → Build complete (proves every app call site resolved against the kit).

### Step 2: Fix the domain hints array

Remove the two unreachable duplicate entries (the SECOND occurrences of `maps.apple.com` and `maps.google.com`). Sort the whole array by descending domain length so the comment's claim ("a more specific domain is always tested before any suffix of it") is actually enforced by construction, and add one line to the comment noting the Code entries are opt-in by folder name.

**Verify**: `swift test --filter KeywordCategorizerTests` → all pass (the github-Code test pins the opt-in behavior).

### Step 3: Music fixture entries

Add 10 Music entries to `accuracy-set.json` matching the existing JSON shape: realistic music links (album reviews, playlist shares, an open.spotify.com track URL, a music.apple.com album URL, a bandcamp release, a soundcloud set, plus keyword-only ones using song/album/playlist/setlist/vinyl phrasing), each `"expected": "Music"`. Update the count assertion in `meetsSeventyPercentAccuracyOnFixtureSet` from `== 40` to `== 50`, and change the accuracy failure message to report per-folder correct/total (build a `[String: (correct: Int, total: Int)]` while scoring and include it in the `#expect` comment string).

**Verify**: `swift test --filter KeywordCategorizerTests` → the accuracy test passes at >= 0.7 with 50 entries. If accuracy lands BELOW 0.7, do NOT edit the fixture to pass; extend the Music keyword table (in-scope file) with the missing terms your entries legitimately use, and note it. If it still fails, STOP and report the per-folder numbers.

### Step 4: The lockstep test

Add `everyDefaultFolderIsFullyWired` to `KeywordCategorizerTests.swift`: for each folder in `Library.defaultFolders` where the folder is not `Library.unsorted`, assert (a) `KeywordCategorizer.keywords[folder]` is non-empty, (b) the accuracy fixture contains at least one entry expecting it, (c) `folderSymbol(for: folder) != "folder"` and (d) `folderColor(for: folder) != folderColor(for: "SomeUnknownFolderName")` (the custom-folder fallback), so a future folder added to defaults without table/fixture/style entries fails this test by name. (b) needs the fixture decoded in this test too — reuse the same decode the accuracy test uses.

**Verify**: `swift test --filter KeywordCategorizerTests` → all pass. Then full `swift test` → all pass, zero warnings.

## Test plan

Covered in Steps 3-4.

## Done criteria

- [ ] `swift test` exits 0; the lockstep test exists and passes; fixture has 50 entries.
- [ ] `ls Sources/Dogear/FolderColor.swift` → No such file; `grep -n "public func folderColor" Sources/DogearKit/FolderStyle.swift` → present.
- [ ] `grep -c "maps.apple.com" Sources/DogearKit/Categorizer.swift` → 1.
- [ ] `git status --porcelain` shows only in-scope files (plus the deletion).

## STOP conditions

- Excerpt mismatch (drift).
- Any `Sources/Dogear/` file fails to compile after the move (means a call-site edit would be needed; that violates scope).
- Step 3 accuracy cannot reach 0.7 after one keyword-table extension round.

## Maintenance notes

- Adding a folder to defaults now requires: defaultFolders, keywords, fixture entries, symbol, color — and the lockstep test names each miss. The store migration from plan 001 delivers the folder to existing users automatically.
- Reviewer: check the Music fixture entries are plausibly real-world (they benchmark the product's headline feature; garbage-in weakens the gate).
