# Contribute to Dogear

Thank you for your help.

## Setup

```bash
git clone https://github.com/freddie-northam/dogear
cd dogear
swift test
```

All logic lives in `Sources/DogearKit`, with unit tests. The SwiftUI app in
`Sources/Dogear` stays thin. Zero third-party dependencies is a hard rule.

## Rules

- `swift test` must pass. New logic needs tests.
- ROADMAP.md records current product decisions. The design spec in
  `docs/superpowers/specs/` is the dated v1 design record; where they
  differ, ROADMAP and the code win.
- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- One concern per pull request.

## Cut a release

1. Set the new version in `VERSION`.
2. Commit, then tag: `git tag v1.0.1 && git push --tags`.
3. The Release workflow runs the tests, builds the app, and attaches
   `Dogear-v1.0.1.zip` to a GitHub release with generated notes.

## Screenshots

Launch the app with `DOGEAR_DATA_DIR=/path/to/demo` to run it against a
demo library, and `DOGEAR_DEMO_FOLDER=Recipes` to open the library on a
folder. The README screenshots come from a demo library, never from a real
one. Capture windows with `screencapture -l <window id>`.

## Live canaries

`CANARY=1 swift test --filter CanaryTests` runs real fetches against TikTok
and X. CI runs these on a daily schedule once the repository has a GitHub
remote; a canary failure means a platform changed its behavior, not that
your change broke something.

## Extension points

### Add a site fetcher

Implement `MetadataFetcher` (`Sources/DogearKit/MetadataFetching.swift`):
`fetch(_:client:) async throws -> FetchedMetadata`. Register the host in
`MetadataService.fetcher(forHost:)` (`Sources/DogearKit/MetadataService.swift`).
A fetcher either parses the page body or calls its own endpoint; see
`parsesPageBody` on `MetadataFetcher`. Add a fixture test under
`Tests/DogearKitTests/Fixtures`. Use `TikTokFetcherTests.swift` or
`XFetcherTests.swift` as the pattern.

### Add a categorizer

Implement `Categorizer` (`Sources/DogearKit/Categorizer.swift`):
`categorize(_:url:folders:) async -> String?`. Wire it in
`CategorizerFactory.make()` (`Sources/DogearKit/LLMCategorizer.swift`). Never
return a folder outside the `folders` list you were passed.

### Storage rules

The library format must stay ready for a future shared-lists feature synced
through iCloud. Keep these rules:

- One JSON document (`Library`, in `Sources/DogearKit/Models.swift`) holds
  the whole library. Do not split it into multiple files.
- Every `Bookmark` keeps a stable `UUID` id. Never reuse or regenerate one.
- Add new `Bookmark` fields as optional only. A missing key must decode as
  `nil`, so an older library file still loads (see `favoritedAt` for an
  example).
- Writes stay atomic, with `.bak` rotation, as in
  `BookmarkStore.saveNow()`.
