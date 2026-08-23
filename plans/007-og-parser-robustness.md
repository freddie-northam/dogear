# Plan 007: Stop the OpenGraph parser from dropping tags with ">" in content or name+property pairs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat dec5931..HEAD -- Sources/DogearKit/OpenGraphParser.swift Tests/DogearKitTests/OpenGraphParserTests.swift`
> If either file changed since this plan was written, compare the "Current
> state" excerpt against the live code before proceeding; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `dec5931`, 2026-08-24

## Why this matters

The parser extracts `og:` metadata from untrusted HTML with two regexes. Two ordinary inputs defeat it silently. First, `<meta property="og:description" content="5 > 3 tips">` dies because the tag regex `[^>]*` stops at the `>` inside the attribute value; the truncated tag has no complete content attribute, so the description is dropped. Second, `<meta property="og:title" name="twitter:title" content="...">` loses the og title because the attribute loop stores whichever of `property`/`name` matched LAST into one variable. Dropped metadata means bare bookmarks with host-path stub titles, and for X pages a missing `og:description` makes `XFetcher` throw and the whole enrichment degrade. These are ordinary patterns on real pages, not adversarial input.

## Current state

Relevant files:

- `Sources/DogearKit/OpenGraphParser.swift` — the whole parser (~90 lines). `parse(html:)` at lines 11-47, `decodeEntities` below it (do not change `decodeEntities`).
- `Tests/DogearKitTests/OpenGraphParserTests.swift` — fixture-backed tests, Swift Testing style. Uses `Bundle.module` fixtures from `Tests/DogearKitTests/Fixtures/` plus inline HTML strings.

Excerpt as of `dec5931` (`Sources/DogearKit/OpenGraphParser.swift:11-31`):

```swift
public static func parse(html: String) -> OpenGraphData {
    var properties: [String: String] = [:]
    // ponytail: regex over string scanning is enough here; fetched HTML is capped at 1 MB.
    // Tag and attribute names are case-insensitive in HTML; attribute values are not.
    let metaPattern = #/(?i)<meta\s+[^>]*>/#
    let attrPattern = #/(?i)(property|name|content)\s*=\s*(?:"([^"]*)"|'([^']*)')/#

    for match in html.matches(of: metaPattern) {
        let tag = String(match.output)
        var property: String?
        var content: String?
        for attr in tag.matches(of: attrPattern) {
            let name = String(attr.output.1).lowercased()
            guard let raw = attr.output.2 ?? attr.output.3 else { continue }
            let value = String(raw)
            if name == "content" { content = value } else { property = value }
        }
        if let property, let content, property.hasPrefix("og:"), properties[property] == nil {
            properties[property] = decodeEntities(content)
        }
    }
```

Toolchain constraint that will bite you: this package builds in Swift language mode v5, where BARE regex literals `/.../` DO NOT COMPILE. Every regex literal must use extended delimiters `#/.../#`, as the existing code does.

Repo conventions: zero third-party deps (no HTML parser libraries; `libxml2` via Foundation is also out of scope for this plan — the regex approach stays, made quote-aware). No em dashes anywhere. Conventional Commits, no AI attribution. A deliberate ceiling gets a `// ponytail:` comment.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Focused tests | `swift test --filter OpenGraphParserTests` | all pass |
| Downstream tests | `swift test --filter "XFetcherTests|MetadataServiceTests"` | all pass |
| Full tests | `swift test` | exit 0, zero warnings |

## Scope

**In scope**:

- `Sources/DogearKit/OpenGraphParser.swift`
- `Tests/DogearKitTests/OpenGraphParserTests.swift`

**Out of scope** (do NOT touch):

- `decodeEntities` and its tests — the double-decode behavior is a recorded ruling.
- `Sources/DogearKit/XFetcher.swift`, `GenericFetcher.swift` — consumers; they must pass unmodified.
- `Tests/DogearKitTests/Fixtures/` — the real-capture fixtures must not be edited; add inline HTML strings in the test file instead.

## Git workflow

- Commit in the worktree; one `fix(parser):` Conventional Commit, imperative capitalized subject, body explains why. Do NOT push.

## Steps

### Step 1: Make the tag match quote-aware

Replace `metaPattern` with a pattern whose body consumes quoted strings atomically so a `>` inside quotes does not end the tag:

```swift
let metaPattern = #/(?i)<meta\s+(?:[^>"']|"[^"]*"|'[^']*')*>/#
```

**Verify**: `swift test --filter OpenGraphParserTests` → existing tests pass.

### Step 2: Prefer property over name explicitly

In the attribute loop, keep separate captures: store `property=` matches into `propertyAttr` and `name=` matches into `nameAttr`; after the loop, `let property = propertyAttr ?? nameAttr`. First occurrence of each wins within a tag (guard with `== nil` before assigning), so a repeated attribute cannot overwrite an earlier one.

**Verify**: `swift build` → Build complete.

### Step 3: Tests

Add to `Tests/DogearKitTests/OpenGraphParserTests.swift` (inline HTML strings, following the existing `fallsBackToTitleTag` style):

1. `parsesContentContainingAGreaterThan` — `<meta property="og:description" content="5 > 3 tips">` yields description `"5 > 3 tips"`.
2. `propertyWinsOverName` — `<meta property="og:title" name="twitter:title" content="Real">` yields title `"Real"`; also assert the reversed attribute order (`name` first, `property` second) yields the same.
3. `singleQuotedContentWithAGreaterThan` — `<meta property='og:title' content='a > b'>` yields title `"a > b"`.
4. `unquotedGreaterThanStillEndsTheTag` — `<meta property="og:title" content="x">trailing<p>` must not swallow `trailing<p>` into the tag (title is `"x"`).

**Verify**: `swift test --filter OpenGraphParserTests` → all pass including 4 new.

### Step 4: Full suite

**Verify**: `swift test` → all pass, zero warnings (the X/TikTok fixture tests prove real-capture pages still parse).

## Test plan

Covered in Step 3; pattern file is the existing `OpenGraphParserTests.swift` inline-string tests.

## Done criteria

- [ ] `swift test` exits 0; the 4 new tests exist and pass.
- [ ] The fixture tests (`parsesOGTagsRegardlessOfAttributeOrder` etc.) pass unmodified.
- [ ] `git status --porcelain` shows only the two in-scope files.

## STOP conditions

- The excerpt above does not match the live file (drift).
- The quote-aware pattern fails to compile under the v5 language mode after one correction attempt (report the compiler error; do not switch to a scanner rewrite on your own).
- Any XFetcher/MetadataService test fails after the change.

## Maintenance notes

- The parser is still a regex engine over untrusted HTML with a documented `ponytail:` ceiling; if a third real-world failure class appears, the upgrade path is a small hand-rolled scanner, not more regex.
- Reviewer: check the new pattern against catastrophic backtracking by eye (the alternation is anchored on distinct first characters, so it is linear).
