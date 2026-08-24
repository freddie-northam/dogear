# Plan 009: Fetch each URL once per enrichment and read downloads in chunks

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`. Commit as soon as the full suite
> is green, BEFORE writing your final report.
>
> **Drift check (run first)**: `git diff --stat 9871687..HEAD -- Sources/DogearKit/HTTPClient.swift Sources/DogearKit/MetadataService.swift Sources/DogearKit/GenericFetcher.swift Sources/DogearKit/XFetcher.swift Sources/DogearKit/TikTokFetcher.swift Sources/DogearKit/MetadataFetching.swift Tests/DogearKitTests/StubHTTPClient.swift Tests/DogearKitTests/HTTPClientTests.swift Tests/DogearKitTests/MetadataServiceTests.swift Tests/DogearKitTests/XFetcherTests.swift Tests/DogearKitTests/TikTokFetcherTests.swift Tests/DogearKitTests/EnrichmentServiceTests.swift`
> On any change since `9871687`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: 006 (DONE)
- **Category**: perf
- **Planned at**: commit `9871687`, 2026-08-24

## Why this matters

Dogear's product bar is "one of the lightest apps on the system", and enrichment is its only sustained network and CPU work. Two structural costs: (1) every enrichment fetches the same URL twice, once via `resolvedURL(for:)` (a GET whose body is discarded) and once via the fetcher's own full GET, so a 200-link Notes import issues 400 requests and 400 TLS handshakes and shows titles later than it could; (2) `data(from:limit:)` accumulates the response one `UInt8` per async iteration, so a 1 MB page costs about a million async-sequence steps and single-byte appends, and a 10 MB thumbnail ten million, per fetch, four fetches in flight during an import. Fixing both roughly halves enrichment network traffic and removes the dominant per-fetch CPU term.

## Current state

- `Sources/DogearKit/HTTPClient.swift` (full file is 60 lines). The protocol:

```swift
public protocol HTTPClient: Sendable {
    func data(from url: URL, limit: Int) async throws -> Data
    func resolvedURL(for url: URL) async throws -> URL
}
```

The byte loop in `URLSessionHTTPClient.data(from:limit:)`:

```swift
let (bytes, response) = try await session.bytes(from: url)
guard let http = response as? HTTPURLResponse else { throw HTTPClientError.noResponse }
guard (200..<300).contains(http.statusCode) else { throw HTTPClientError.badStatus(http.statusCode) }
var data = Data()
data.reserveCapacity(min(limit, Int(http.expectedContentLength.clamped())))
for try await byte in bytes {
    data.append(byte)
    if data.count > limit { throw HTTPClientError.tooLarge }
}
return data
```

`resolvedURL(for:)` does a GET via `session.bytes(from:)`, cancels the task, and returns `response.url ?? url` (a GET, not HEAD, because t.co rejects HEAD).

- `Sources/DogearKit/MetadataService.swift` (full file is 27 lines): `fetch(for:)` resolves first, routes by the RESOLVED host via `static func fetcher(forHost:)`, then calls the fetcher. The three fetchers (`GenericFetcher`, `XFetcher`, `TikTokFetcher`) each take `(url, client)` and call `client.data(from:limit:)`; TikTok calls it on its oEmbed endpoint URL, not the page URL.
- `Tests/DogearKitTests/StubHTTPClient.swift`: `StubHTTPClient(responses: [URL: Data])` with `var redirects: [URL: URL]` (matched by canonical form in `resolvedURL`), `var failEverything`, `requestedURLs()` via an actor log. Tests across `MetadataServiceTests`, `XFetcherTests`, `TikTokFetcherTests`, `EnrichmentServiceTests` build on it (`EnrichmentServiceTests` also has an `InterceptingHTTPClient` that wraps a stub).
- `Tests/DogearKitTests/HTTPClientTests.swift`: tests the UA constant and the STUB's limit behavior; the real client's cap is NOT tested (no local server in the suite).

Conventions: zero third-party deps; no em dashes; Conventional Commits, no AI attribution; kit test-first; `HTTPClient` conformers must stay `Sendable`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused | `swift test --filter "HTTPClientTests\|MetadataServiceTests\|XFetcherTests\|TikTokFetcherTests\|EnrichmentServiceTests"` | all pass |
| Full | `swift test` | exit 0, zero warnings |
| Live canaries | `CANARY=1 swift test --filter CanaryTests` | 2 pass (needs network; run once at the end) |

## Scope

**In scope**: the twelve files in the drift check.

**Out of scope**: `EnrichmentService.swift` (it consumes `MetadataService.fetch(for:)`, whose signature and return tuple stay identical); `AppModel.swift`; `CanaryTests.swift` (run, not edited).

## Git workflow

- Commit in the worktree; `perf(kit):` Conventional Commits (one per step is fine). Do NOT push.

## Steps

### Step 1: Chunked reads with the cap enforced per chunk (test-first)

Change `data(from:limit:)` to accumulate chunks rather than bytes. `URLSession.AsyncBytes` exposes only a byte sequence; the chunked alternative that keeps STREAMING enforcement (reject past the cap without downloading the rest) is a `URLSessionDataDelegate`. Implement a small private delegate class holding a `CheckedContinuation`, appending `didReceive data:` chunks to a buffer, cancelling the task and failing the continuation with `.tooLarge` when the buffer exceeds `limit`, and completing on `didCompleteWithError`. Keep the status-code check (`badStatus`) using the response received in `didReceive response:`. The session must be created with the delegate: since `URLSession(configuration:delegate:delegateQueue:)` takes one delegate per session, create a per-request session inside `data(from:limit:)` (ephemeral, same config) and `finishTasksAndInvalidate()` on completion, OR keep one session and route by task identifier in a shared delegate. Prefer the per-request session for simplicity; the session cost is negligible next to the request.

Test-first, in `HTTPClientTests.swift`: the real client's cap has never been tested because there is no local server. Add one using `URLProtocol`: a test-local `StubURLProtocol` subclass registered in a custom `URLSessionConfiguration.protocolClasses` that serves a canned 2,000-byte body for any URL. This needs `URLSessionHTTPClient` to accept a configuration: add `public init(configuration: URLSessionConfiguration)` alongside the existing `init()` (which calls it with the ephemeral config). Tests: `realClientThrowsTooLargePastTheLimit` (limit 1,000 → `.tooLarge`) and `realClientReturnsTheWholeBodyUnderTheLimit` (limit 10,000 → 2,000 bytes). Confirm the first FAILS to compile/pass before implementing the init, then passes after.

**Verify**: `swift test --filter HTTPClientTests` → all pass including 2 new. `grep -n "for try await byte" Sources/DogearKit/HTTPClient.swift` → no match.

### Step 2: One fetch per enrichment (test-first)

Extend the protocol with a method that returns both the body and the final URL:

```swift
func fetch(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL)
```

Implement it in `URLSessionHTTPClient` via the same delegate path (the final URL is `task.currentRequest?.url ?? response.url`). Keep `data(from:limit:)` (thumbnails and oEmbed use it) and keep `resolvedURL(for:)` only if a caller remains after Step 3; if none remains, delete it from the protocol and both conformers.

In `StubHTTPClient`, implement `fetch` as: apply `redirects` (canonical-match, same as `resolvedURL`) to get the final URL, then return `responses[finalURL]` (falling back to `responses[url]`), throwing `badStatus(404)` when neither exists, logging the request. `InterceptingHTTPClient` in `EnrichmentServiceTests` must forward the new method (count it as a call for its trigger logic, consistent with how it counts `data`).

**Verify**: `swift build` → Build complete.

### Step 3: Route on the final host after a single fetch

Restructure `MetadataService.fetch(for:)`:

1. `let (body, final) = try await client.fetch(url, limit: FetchLimit.html)`, on throw, return `(url, nil)` as today.
2. Route with `fetcher(forHost: final.host)`.
3. For fetchers that parse the page body (`GenericFetcher`, `XFetcher`): give `MetadataFetcher` a second entry point `func parse(body: Data, url: URL) throws -> FetchedMetadata` and call it with the already-downloaded body, so no second request happens. For `TikTokFetcher` (its metadata comes from the oEmbed endpoint, not the page), keep calling its existing `fetch(_:client:)` with the FINAL url (this is one page GET plus one oEmbed GET, down from two page GETs plus one oEmbed). Give `MetadataFetcher` a default `parse` that throws `HTTPClientError.noResponse` so TikTok need not implement it; `MetadataService` decides per fetcher via a `usesPageBody: Bool` static or by `is TikTokFetcher` check, pick the simpler; a protocol property `static var parsesPageBody: Bool` with a default of `true` and TikTok overriding to `false` is the cleaner shape.
4. Return `(final, metadata)`.

Existing tests: `MetadataServiceTests.resolvesShortLinkThenRoutesByFinalHost` and the enrichment redirect tests exercise the redirect → route → parse path through the stub's `redirects` map; they must pass with the new single-fetch flow. Add `fetchesTheResolvedPageExactlyOnce` in `MetadataServiceTests`: a generic page behind a redirect; after `fetch(for:)`, `stub.requestedURLs()` contains the page URL exactly once (it previously appeared twice).

**Verify**: `swift test --filter "MetadataServiceTests|XFetcherTests|EnrichmentServiceTests"` → all pass including the new test.

### Step 4: Full suite and live canaries

**Verify**: `swift test` → all pass, zero warnings. `CANARY=1 swift test --filter CanaryTests` → 2 pass (proves real X and TikTok still parse through the new path; if a canary fails on a network error rather than a parse error, retry once and report).

## Test plan

Covered in Steps 1-3; patterns: the existing stub-based tests and `CanaryTests` for the live check.

## Done criteria

- [ ] `swift test` exits 0; new tests from Steps 1 and 3 exist and pass; canaries pass.
- [ ] `grep -n "for try await byte" Sources/DogearKit/HTTPClient.swift` → no match.
- [ ] `grep -rn "resolvedURL(for" Sources/DogearKit/` → either no matches (removed) or only inside `HTTPClient.swift` with no caller in `MetadataService.swift`.
- [ ] `MetadataService.fetch(for:)` signature unchanged: `func fetch(for url: URL) async -> (resolvedURL: URL, metadata: FetchedMetadata?)`.
- [ ] `git status --porcelain` shows only in-scope files.

## STOP conditions

- Excerpt mismatch (drift).
- The `URLProtocol`-based cap test cannot be made to work with the delegate-based client after one honest attempt (report; a `URLProtocol` stub and a data delegate are a known-good combination, so a failure likely indicates a session-configuration mistake worth a second look before stopping).
- A canary fails with a PARSE error (metadata nil or wrong) rather than a network error: the single-fetch path changed real-page behavior; report the metadata you got.
- `MetadataService.fetch(for:)`'s signature would need to change (it must not; `EnrichmentService` is out of scope).

## Maintenance notes

- Any future fetcher must decide whether it parses the page body (`parsesPageBody`) or calls its own endpoint; CONTRIBUTING's extension-point docs should mention this after the publication plan.
- Reviewer: check that the delegate's continuation is resumed exactly once on every path (success, tooLarge, badStatus, transport error), and that the per-request session is invalidated.
