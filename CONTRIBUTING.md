# Contributing to Dogear

Thanks for helping.

## Setup

```bash
git clone https://github.com/northamf/dogear
cd dogear
swift test
```

All logic lives in `Sources/DogearKit` and is unit-tested. The SwiftUI app in
`Sources/Dogear` stays thin. Zero third-party dependencies is a hard rule.

## Rules

- `swift test` must pass. New logic needs tests.
- The design spec lives in `docs/superpowers/specs/`. Read it before large changes.
- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- One concern per pull request.

## Live canaries

`CANARY=1 swift test --filter CanaryTests` runs real fetches against TikTok
and X. CI runs these daily; a canary failure means a platform changed its
behavior, not that your change broke something.

## Extension points

### Add a site fetcher

Implement `MetadataFetcher` (`Sources/DogearKit/MetadataFetching.swift`):
`fetch(_:client:) async throws -> FetchedMetadata`. Register the host in
`MetadataService.fetcher(forHost:)` (`Sources/DogearKit/MetadataService.swift`).
Add a fixture test under `Tests/DogearKitTests/Fixtures`, following
`TikTokFetcherTests.swift` or `XFetcherTests.swift`.

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
