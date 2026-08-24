# Dogear

A small macOS menu bar app that saves and files links. Zero third-party
dependencies, local-only storage.

## Build and test

- `swift test` runs the full suite.
- `PERF=1 swift test --filter BookmarkStoreTests` runs the performance
  benchmarks.
- `CANARY=1 swift test --filter CanaryTests` runs live fetches against
  TikTok and X. Do not run these on every change; they hit real servers.
- `Scripts/make-app.sh` builds `build/Dogear.app`.

## Layout

- `Sources/DogearKit` holds all logic. Every file here needs tests.
- `Sources/Dogear` holds the SwiftUI app. It stays thin. By decision, it
  has no automated tests.

## Hard rules

- Zero third-party dependencies. Use only Apple's frameworks.
- A new stored field on `Bookmark` or `Library` must be optional. A
  missing key must decode as `nil`, so an older library file still loads.
- A categorizer never returns a folder outside the list it was passed.
- No notifications, ever.
- Only `http` and `https` URLs become bookmarks. Check
  `URLCleaner.isCapturable` before you add a new capture path.

## Conventions

- Swift language mode v5: write regex literals as `#/.../#`.
- No em dashes anywhere: not in code comments, commits, or docs.
- Conventional Commits, imperative capitalized subject, no AI attribution.
- A `// ponytail:` comment marks a deliberate ceiling and its upgrade path.
- Docs follow ASD-STE100 Simplified Technical English.

## Pointers

- `CONTRIBUTING.md`: how to add a fetcher or a categorizer.
- `ROADMAP.md`: what shipped and what the team deferred, and why.
- `plans/README.md`: the improvement backlog.
