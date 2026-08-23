# Plan 003: Stop trimming URLs at apostrophes and harden markdown export

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 5f06577..HEAD -- Sources/DogearKit/URLCleaner.swift Sources/DogearKit/Models.swift Tests/DogearKitTests/URLCleanerTests.swift Tests/DogearKitTests/ModelsTests.swift`
> On any change since `5f06577`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `5f06577`, 2026-08-24

## Why this matters

Two output-correctness bugs. First, the URL extractor trims every detected link at the first apostrophe, raw `'` or percent-encoded `%27` — those characters are in `markupMarkers`, added to cut HTML junk like `</div>` off links extracted from Notes bodies. But apostrophes are legal and common in real URLs (any Wikipedia article about a possessive), so a saved bookmark silently points at a truncated, usually 404, page. Second, `Bookmark.markdownLink` escapes square brackets in the title but interpolates the URL raw: a `)` inside a URL path (Wikipedia disambiguation pages) terminates the markdown link early, and a page-controlled title containing a decoded newline splits the exported list into broken lines. Copy as Markdown then corrupts whatever document the user pastes into.

## Current state

Relevant files:

- `Sources/DogearKit/URLCleaner.swift` — `markupMarkers` and `trimmedAtMarkup` (excerpt below); `allHTTPURLs(in:)` calls `trimmedAtMarkup` on every detected URL.
- `Sources/DogearKit/Models.swift` — `Bookmark.markdownLink` and `markdownList` extension (excerpt below).
- `Tests/DogearKitTests/URLCleanerTests.swift` — has `trimsExtractedURLAtHTMLMarkup` covering `<` and `"` cases.
- `Tests/DogearKitTests/ModelsTests.swift` — has markdown tests including bracket escaping.

`URLCleaner` excerpt (`Sources/DogearKit/URLCleaner.swift:32-43`):

```swift
static let markupMarkers = ["<", ">", "\"", "'", "%3C", "%3E", "%22", "%27", "%3c", "%3e"]

static func trimmedAtMarkup(_ url: URL) -> URL? {
    let text = url.absoluteString
    var cut = text.endIndex
    for marker in markupMarkers {
        if let found = text.range(of: marker)?.lowerBound, found < cut { cut = found }
    }
    guard cut != text.endIndex else { return url }
    return URL(string: String(text[..<cut]))
}
```

`Models.swift` excerpt (`Sources/DogearKit/Models.swift:44-59`):

```swift
extension Bookmark {
    /// A `[title](url)` markdown link. Square brackets in the title become
    /// parentheses so the link text cannot break the markdown syntax.
    public var markdownLink: String {
        let safeTitle = title
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        return "[\(safeTitle)](\(url))"
    }

    /// A markdown bullet list, one `- [title](url)` line per bookmark.
    public static func markdownList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.map { "- \($0.markdownLink)" }.joined(separator: "\n")
    }
}
```

Conventions: no em dashes anywhere; Conventional Commits, no AI attribution; kit changes test-first; language mode v5 (bare regex literals do not compile; use `#/.../#` if a regex is needed, though none should be here).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter "URLCleanerTests\|ModelsTests"` | all pass |
| Full | `swift test` | exit 0, zero warnings |

## Scope

**In scope**: the four files listed above.

**Out of scope**: `OpenGraphParser.swift` (entity decoding is a recorded ruling); `LibraryWindow.swift` (the copy actions consume `markdownLink` unchanged); the `<`, `>`, `"`, and their percent forms in `markupMarkers` (they stay — they are the fix for real HTML junk).

## Git workflow

- Commit in the worktree; `fix(kit):` Conventional Commits. Do NOT push.

## Steps

### Step 1: Narrow the markup markers (test-first)

Write the failing test in `URLCleanerTests.swift`:

```swift
@Test func keepsApostrophesInExtractedURLs() {
    let urls = URLCleaner.allHTTPURLs(in: "read https://en.wikipedia.org/wiki/It%27s_a_Wonderful_Life and https://a.com/don't-stop")
    #expect(urls.count == 2)
    #expect(urls[0].absoluteString.contains("%27"))
    #expect(urls[1].absoluteString.contains("'") || urls[1].absoluteString.contains("%27"))
}
```

Run it, confirm it FAILS against current code. Then remove `"'"` and `"%27"` from `markupMarkers`. Confirm the test passes and `trimsExtractedURLAtHTMLMarkup` still passes.

Note: NSDataDetector may percent-encode the raw apostrophe; the second assertion accepts either form. If the detector splits the second URL at the apostrophe entirely (count comes back wrong), adjust the fixture text to use only the `%27` form and note the deviation.

**Verify**: `swift test --filter URLCleanerTests` → all pass.

### Step 2: Harden markdownLink (test-first)

Failing tests in `ModelsTests.swift` (follow the existing markdown test style):

1. `markdownLinkSurvivesParenthesesInURL` — a bookmark with url `https://en.wikipedia.org/wiki/Swift_(programming_language)`: the rendered link must round-trip, which angle-bracket delimiters guarantee: expect `[Title](<https://en.wikipedia.org/wiki/Swift_(programming_language)>)`.
2. `markdownLinkFlattensNewlinesInTitle` — title `"Line one\nLine two"` renders as `[Line one Line two](<...>)` (newlines and control characters collapse to single spaces).

Then implement: in `markdownLink`, collapse any character in `CharacterSet.newlines` plus control characters in the title to a single space (and collapse runs), keep the bracket replacement, and wrap the URL in angle brackets: `[\(safeTitle)](<\(url)>)`. Angle-bracket URL delimiters are standard CommonMark; they neutralize `(`/`)` and spaces without altering the URL itself. Update any existing markdown test expectations to the angle-bracket form.

**Verify**: `swift test --filter ModelsTests` → all pass.

### Step 3: Full suite

**Verify**: `swift test` → all pass, zero warnings.

## Test plan

Covered in Steps 1-2; pattern files are the two existing test files.

## Done criteria

- [ ] `swift test` exits 0; the 3 new tests exist and pass.
- [ ] `grep -n "markupMarkers" Sources/DogearKit/URLCleaner.swift` shows no `'` and no `%27` entries.
- [ ] `grep -n "](<" Sources/DogearKit/Models.swift` shows the angle-bracket form.
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- Excerpt mismatch (drift).
- Existing markdown tests assert a shape that angle brackets cannot satisfy for a reason not covered here (report the failing expectation verbatim).
- NSDataDetector behavior with apostrophes makes Step 1's test impossible in both raw and encoded forms.

## Maintenance notes

- Plan 014 (file export) will reuse `markdownList`; the angle-bracket form is what makes exported files safe, so do not "simplify" it away later.
- Reviewer: confirm the runs-of-whitespace collapse cannot alter titles that legitimately contain double spaces beyond cosmetics.
