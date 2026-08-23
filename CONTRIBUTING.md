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
