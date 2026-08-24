# Plan 012: Make every document tell the truth before the repository goes public

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`. Commit as soon as verification
> is green, BEFORE writing your final report.
>
> **Drift check (run first)**: `git diff --stat 524e4d4..HEAD -- README.md ROADMAP.md CONTRIBUTING.md docs/superpowers/specs/2026-08-23-dogear-design.md .github/workflows/ Scripts/make-app.sh Sources/Dogear/SettingsView.swift`
> This plan is scheduled LAST in the wave; source files may have changed
> since `524e4d4` (plans 009 and 014). For docs, re-read the CURRENT feature
> set from `ROADMAP.md`'s git history and `Sources/Dogear/LibraryWindow.swift`'s
> menu labels before writing, and describe what exists at YOUR HEAD, not at
> this plan's SHA. A drift in the Info.plist heredoc or SettingsView version
> line IS a stop.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001-011, 014 (all landed before this runs)
- **Category**: docs / dx
- **Planned at**: commit `524e4d4`, 2026-08-24

## Why this matters

The repository is about to go public under MIT and the README is its front door. Today it teaches a manual Notes workflow the app automates with one click, never mentions list view, sorting, favourites, QR codes, the Music folder, or the Services menu entry, and points at a GitHub URL that does not exist yet. The binding design spec disagrees with shipped code in six places and CONTRIBUTING tells every contributor to read it first. ROADMAP omits two shipped features. There is no repo-level `CLAUDE.md`, so every agent session rediscovers the four hard rules or breaks one. The app version is a hardcoded string in two files. `Scripts/make-app.sh`, the only path that produces the artifact users download, never runs in CI and has already broken silently once. And the spec promises a notarized DMG while the script produces an ad-hoc signature: a decision drift between doc and code. Ruling for this plan: document the truth (ad-hoc, unsandboxed, source-build or GitHub release of an ad-hoc-signed app) and leave notarization as a roadmap item gated on a Developer ID.

## Current state

- `README.md` (53 lines): sections How it works / Move your links from Apple Notes (manual select-all-copy flow) / Install (release download + `git clone https://github.com/freddie-northam/dogear`) / Privacy / License, plus a trailing "See ROADMAP.md for what comes next." Folder list in the intro: "recipes, restaurants, shows, articles".
- `ROADMAP.md`: "Shipped (v1.x)" ends at "Import from Apple Notes"; "Next up: Nothing is scheduled"; Deferred list; Principles (no notifications, zero deps, local-only).
- `CONTRIBUTING.md` line 19: "The design spec lives in `docs/superpowers/specs/`. Read it before large changes." Line ~21+: "Live canaries ... CI runs these daily".
- `docs/superpowers/specs/2026-08-23-dogear-design.md` line 4: `Status: approved design, ready for implementation planning`. Known drifts vs code: §3 says macOS 15 (code: 15.4) and "Xcode project" (code: SwiftPM); §4 describes the original popover (code: v4 redesign); §6 specifies `@Generable` (code: free-text plus validation, awaiting Xcode 26); §7 first-run Launch at Login offer and §8 custom-folder symbol palette (both deferred in ROADMAP); §2 export out of scope (code: markdown export ships); §9 README screenshots (none exist); §3 "notarized DMG" (code: ad-hoc signing); default folders list lacks Music; cards no longer show source domain.
- `.github/workflows/ci.yml` (18 lines, shown in full above the plan's excerpt list): one `test` job, `actions/checkout@v4`, `swift test`. `canary.yml`: schedule + dispatch, same checkout tag.
- `Scripts/make-app.sh:27`: `<key>CFBundleShortVersionString</key><string>1.0.0</string>`; line 48: `codesign --force --sign - "$APP"`.
- `Sources/Dogear/SettingsView.swift:37`: `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"`.
- No `CLAUDE.md` in the repo root.
- Feature surface to document (read current menu labels in `Sources/Dogear/LibraryWindow.swift` and `CapturePopover.swift` to confirm exact strings): grid/list view toggle, sort menu (Last Saved, Oldest First, Title, By Site), Favourites, notes, QR code, Copy as Markdown, Open in Maps (Restaurants), drag in/out, Import from Notes (one click, permission prompt), Import Bookmarks File and Export Library (plan 014), Save to Dogear in the Services menu (plan 015), File These for Me, Refresh Metadata, Music folder.

Conventions: ASD-STE100 Simplified Technical English for all docs (one topic per sentence, active voice, simple tenses, no `-ing` forms outside technical names, define abbreviations); NO em dashes anywhere; Conventional Commits, no AI attribution; keep the existing README voice (short numbered steps).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Bundle | `Scripts/make-app.sh` | ends with "Built build/Dogear.app" |
| Version check | `plutil -extract CFBundleShortVersionString raw -o - build/Dogear.app/Contents/Info.plist` | matches `cat VERSION` |
| Workflow syntax | `python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in sys.argv[1:]]" .github/workflows/*.yml` | exit 0 (PyYAML present on macOS python3; if not, `ruby -ryaml -e 'ARGV.each{|f| YAML.load_file f}' .github/workflows/*.yml`) |
| Em-dash scan | `grep -rn $'\xe2\x80\x94' README.md ROADMAP.md CONTRIBUTING.md CLAUDE.md docs/ .github/ Scripts/` | no output |
| Full tests | `swift test` | exit 0 |

## Scope

**In scope**: `Sources/Dogear/LibraryWindow.swift` (string literals only, Step 7), `README.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `docs/superpowers/specs/2026-08-23-dogear-design.md` (append-only; see Step 4), `.github/workflows/ci.yml`, `.github/workflows/canary.yml`, `.github/dependabot.yml` (create), `CLAUDE.md` (create), `VERSION` (create), `Scripts/make-app.sh` (version line only), `Sources/Dogear/SettingsView.swift` (fallback string only).

**Out of scope**: any other source file; the spec's existing body text (annotate, never rewrite); screenshots (they need a human with the running app; note their absence honestly instead).

## Git workflow

- Commit in the worktree; one commit per logical group: `docs:` (README/ROADMAP/CONTRIBUTING/spec), `docs:` (CLAUDE.md), `chore:` (VERSION + scripts + SettingsView), `ci:` (workflows + dependabot). Do NOT push.

## Steps

### Step 1: README tells the truth

Rewrite sections, keeping the voice:

- Intro folder list becomes "recipes to make, restaurants to visit, shows to watch, music to hear, articles to read".
- Replace "Move your links from Apple Notes" with a one-click flow: open the Library, click the plus button, choose Import from Notes, click Import; macOS asks for permission one time; Dogear saves every link it finds. Keep a one-line note that pasting text with many links also works.
- Add a short "In the library" section (STE bullets): grid or list view; sort by last saved, oldest first, title, or site; star favourites; add a note to a bookmark; show a QR code to open a link on your phone; copy a bookmark or a folder as Markdown; import a browser bookmarks file; export the library to a Markdown file; File These for Me runs auto-filing over Unsorted.
- Add a "From any app" line: select a link, then choose Services, Save to Dogear from the right-click menu (mention it may need enabling in System Settings, Keyboard, Keyboard Shortcuts, Services).
- Install: keep the release download sentence but make it honest: "Releases are built with `Scripts/make-app.sh` and signed with an ad-hoc signature. macOS may ask you to confirm the first launch." Keep the source-build block. The GitHub URL stays as the intended public location; add nothing that claims it exists today.
- Privacy: add one sentence: "Import from Notes and Save to Dogear read only what you choose to import or select."
- Screenshots: do not fabricate; add no placeholder text.

**Verify**: em-dash scan → no output; `grep -c "Import from Notes" README.md` ≥ 1; `grep -c "Select all" README.md` → 0.

### Step 2: ROADMAP and CONTRIBUTING

- ROADMAP Shipped: add lines for list view and sorting; the Music folder; Refresh Metadata and File These for Me; Services menu capture; browser bookmarks import and Markdown file export (confirm plan 014 landed at your HEAD via `git log --oneline | grep -i bookmarks`; if it did not, omit that line and say so in NOTES). Add to Deferred: "Notarized releases: gated on an Apple Developer ID; releases are ad-hoc signed today." and "Notes importer v2: per-folder selection and incremental runs (design recorded in plans/013)".
- CONTRIBUTING line 19: change to "ROADMAP.md records current product decisions. The design spec in `docs/superpowers/specs/` is the dated v1 design record; where they differ, ROADMAP and the code win." Add to the extension-points section one line: "A fetcher either parses the page body or calls its own endpoint; see `parsesPageBody` on `MetadataFetcher`" (only if plan 009 landed; check `grep -rn parsesPageBody Sources/DogearKit/`). Fix the canary sentence to "CI runs these on a daily schedule once the repository has a GitHub remote."

**Verify**: em-dash scan → no output.

### Step 3: CLAUDE.md

Create a repo-root `CLAUDE.md`, under 60 lines, STE:

- Build and test commands: `swift test`; `PERF=1 swift test --filter BookmarkStoreTests`; `CANARY=1 swift test --filter CanaryTests`; `Scripts/make-app.sh`.
- Layout: logic in `Sources/DogearKit` (tested); the SwiftUI app in `Sources/Dogear` stays thin and has no automated tests by decision.
- Hard rules: zero third-party dependencies; new stored fields on `Bookmark`/`Library` must be optional; a categorizer never returns a folder outside the passed list; no notifications, ever; only http and https URLs become bookmarks (`URLCleaner.isCapturable`).
- Conventions: language mode v5, so regex literals use `#/.../#`; no em dashes anywhere; Conventional Commits with imperative capitalized subjects and no AI attribution; `// ponytail:` comments mark a deliberate ceiling and its upgrade path; ASD-STE100 for docs.
- Pointers: `CONTRIBUTING.md` for extension points, `ROADMAP.md` for decisions, `plans/README.md` for the improvement backlog.

**Verify**: `wc -l CLAUDE.md` → under 60; em-dash scan → no output.

### Step 4: Spec status annotation (append-only)

Change line 4 to `Status: dated v1 design record. See the "Drift since approval" section at the end; ROADMAP.md and the code are current.` Append a final section `## Drift since approval (2026-08-24)` listing each drift as one line with the commit or plan that caused it: macOS 15.4 target (NSPasteboard API); SwiftPM instead of an Xcode project; popover v4 redesign; free-text LLM prompt plus validation pending Xcode 26 (`@Generable` still the goal); Launch at Login offer and custom-folder palette deferred (ROADMAP); markdown export shipped; Music folder added; card captions drop the domain; releases ad-hoc signed (notarization deferred); no README screenshots yet. Do not edit any other line of the spec.

**Verify**: `git diff --stat` on the spec shows additions only plus the one status line; em-dash scan → no output.

### Step 5: Single source of truth for the version

Create `VERSION` containing `1.0.0` and a trailing newline. In `Scripts/make-app.sh`, replace the literal in the `CFBundleShortVersionString` line with a shell substitution from the file: since the plist is a quoted heredoc (`<<'PLIST'`), read the version into a variable before the heredoc (`VERSION="$(tr -d '[:space:]' < VERSION)"`) and switch the heredoc delimiter to an unquoted `PLIST` ONLY if no other `$` or backtick appears inside it (check first; if any does, escape them). In `SettingsView.swift:37`, change the fallback literal to `"0.0.0"` so a wrong fallback is visibly wrong rather than plausibly right.

**Verify**: `Scripts/make-app.sh` → Built; `plutil -extract CFBundleShortVersionString raw -o - build/Dogear.app/Contents/Info.plist` → `1.0.0`; `swift build` → Build complete.

### Step 6: CI packages the app and pins its supply chain

- `ci.yml`: add a second job `package` (runs-on macos-15, timeout 30) that checks out and runs `Scripts/make-app.sh`, then `test -d build/Dogear.app`. Add a `perf` job running `PERF=1 swift test --filter BookmarkStoreTests`.
- Pin `actions/checkout` in both workflows to a full commit SHA with the version in a trailing comment (look up the current v4 tag's SHA with `git ls-remote https://github.com/actions/checkout refs/tags/v4.2.2` or the latest v4.x tag; record which tag you pinned in NOTES). Add `persist-credentials: false` under `with:`.
- Create `.github/dependabot.yml` for the `github-actions` ecosystem, weekly.

**Verify**: YAML parse command → exit 0; `grep -c "actions/checkout@[0-9a-f]\{40\}" .github/workflows/ci.yml .github/workflows/canary.yml` → 1 each.

### Step 7: Copy fixes carried from plans 013 and 014 (in `Sources/Dogear/LibraryWindow.swift`, copy strings only)

Three user-facing strings need correcting; change ONLY string literals, no logic:

- The Notes folder picker buttons read "Select All" / "Select None"; change to "Select all" / "Select none" (sentence case, matching the rest of the app).
- The Notes import result: after incremental cursors, a repeat import that finds no CHANGED notes currently reports "No links found in your notes.", which reads as failure. Locate where that message is chosen and, when at least one selected folder had a cursor (an incremental read), use "No new links since your last import." instead. Keep the original wording for a first full read that truly finds nothing. If distinguishing the two cases requires more than reading a value already in scope at that site, STOP and report rather than restructuring.
- The bookmarks-file import result "All N were already saved." has no singular; add "This link was already saved." for N == 1, mirroring the Notes importer.

**Verify**: `swift build` → Build complete; `grep -c "Select All" Sources/Dogear/LibraryWindow.swift` → 0; `grep -c "No new links since your last import." Sources/Dogear/LibraryWindow.swift` → 1.

### Step 8: Full suite

**Verify**: `swift test` → all pass, zero warnings.

## Test plan

Docs plan: the gates are the scans, the plist extraction, the YAML parse, and the unchanged test suite.

## Done criteria

- [ ] Em-dash scan over all in-scope docs → no output.
- [ ] `plutil` shows the version from `VERSION`; `grep -rn '"1.0.0"' Sources/ Scripts/` → no matches.
- [ ] `CLAUDE.md` exists, under 60 lines.
- [ ] Both workflows pin checkout to a 40-char SHA; `.github/dependabot.yml` exists.
- [ ] Spec diff is additions plus the status line only.
- [ ] `swift test` exits 0; `git status --porcelain` shows only in-scope files (build/ ignored).

## STOP conditions

- The Info.plist heredoc or the SettingsView version line differs from the excerpts (drift).
- The heredoc contains `$` or backticks that would expand once unquoted and cannot be escaped cleanly (report; fall back to `sed` substitution of a placeholder token instead of unquoting).
- You cannot determine a checkout SHA (no network): pin nothing, leave `@v4`, and report it.

## Maintenance notes

- Screenshots remain the one honest gap; capture two (popover, library) from a release build and add them under `assets/` in a follow-up.
- Cutting a release is now: edit `VERSION`, tag, run `Scripts/make-app.sh`, attach the app. A tag-triggered release workflow is the natural next CI step once the remote exists.
