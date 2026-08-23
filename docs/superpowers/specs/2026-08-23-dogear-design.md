# Dogear: design specification

Date: 2026-08-23
Status: approved design, ready for implementation planning

## 1. Purpose

Dogear is a small open source macOS app. It captures links from TikTok, X, and the web, and it files them into folders such as Recipes, Restaurants, Shows, and Articles. The app must stay clean and lightweight: native code, no server, no accounts, no third-party dependencies.

## 2. Scope

### In scope for v1

- Menu bar app with a quick-add popover.
- Copied-link detection: the menu bar icon lights up when the clipboard holds a URL.
- Library window with folders, thumbnails, and search.
- Automatic metadata fetch (title, author, thumbnail) per site.
- Automatic categorisation: on-device LLM on macOS 26+, keyword rules otherwise.
- Manual re-file, edit, and delete.
- Done state with a searchable Archive.
- Local JSON storage.
- MIT license, README, and contribution notes.

### Out of scope for v1

- Global hotkey.
- iOS capture, browser extension, sync, and export.
- Instagram support beyond the generic fallback (Instagram requires login for metadata).

## 3. Platform and stack

- Swift + SwiftUI, `MenuBarExtra` for the menu bar presence.
- Deployment target: macOS 15. The LLM path activates on macOS 26+ at runtime.
- Zero third-party packages.
- Xcode project in a public GitHub repository. Later releases ship as a notarized DMG.

## 4. Capture flow

**Copied-link detection.** The app polls `NSPasteboard.general.changeCount` on a 1-second timer. This is an integer comparison with no content read and no measurable CPU cost; it is the only mechanism macOS offers, and it is what every clipboard tool uses. When the count changes, pattern detection checks for a URL shape without a content read. On a match, the menu bar icon changes from `bookmark` to `bookmark.fill`. Nothing appears on screen. With Universal Clipboard, a link copied on iPhone lights the icon on the Mac. A "Detect copied links" setting (default on) disables the timer entirely.

1. The user clicks the menu bar icon. A popover opens.
2. If the clipboard contains a URL, the URL field is pre-filled. Universal Clipboard carries links copied on iPhone. The app uses NSPasteboard pattern detection to check for a URL without a content read, and reads the clipboard only on a positive match. This limits macOS 15 pasteboard privacy prompts to one grant.
3. Only `http` and `https` URLs are accepted. The app rejects `javascript:`, `file:`, `data:`, and every other scheme. When the clipboard holds text with an embedded URL, the app extracts the first URL.
4. The user presses Return. The app saves the bookmark immediately and the popover closes. Capture is fire-and-forget: no folder pick, no form, no notification. The library shows the result of auto-filing later.
5. If the URL is already saved, the app does not create a duplicate. Dedupe compares the redirect-resolved URL with known tracking parameters (`utm_*` and similar) stripped. The existing bookmark moves to the top and the popover shows a short "already saved" hint.

**Invariant: a save never blocks on the network and never fails because of the network.** The bookmark record is written first with the bare URL. Enrichment runs in the background and updates the record when results arrive. A failed fetch leaves an editable bare bookmark.

## 5. Enrichment

A `MetadataFetcher` protocol with three implementations. The app first follows HTTP redirects to the final URL, then selects the fetcher by domain. Redirect resolution is what handles `vm.tiktok.com` short links from the TikTok share sheet.

| Site | Method | Verified facts |
| --- | --- | --- |
| TikTok | Public oEmbed endpoint (`www.tiktok.com/oembed?url=`) | Returns caption as `title`, `author_name`, `thumbnail_url`. No API key. Thumbnail URLs are signed and expire. |
| X / Twitter | HTML fetch, parse OpenGraph tags | Works only with a browser user-agent string. `og:description` holds the tweet text. `og:title` is junk ("jack (@jack) on X"), so the display title is composed as author + truncated tweet text. |
| Generic | HTML fetch, parse OpenGraph tags, fall back to `<title>` | Covers articles, YouTube, blogs. |

Rules that apply to all fetchers:

- Send a pinned browser user-agent string on every HTML fetch. URLSession's default user-agent gets served JS shells.
- Download the thumbnail at save time into a local cache directory. Never hot-link remote thumbnail URLs.
- Enrichment is best-effort. Any failure degrades to a bare bookmark. This also protects against X changing its unauthenticated behavior again.
- Resource caps on every fetch: read at most 1 MB of HTML, 10 MB of thumbnail, 10 seconds per request. A thumbnail is cached only after it decodes as an image.
- Fetched HTML is parsed by pure string scanning. No WebView, no script execution. Fetched pages are untrusted input.

## 6. Categorisation

One `Categorizer` interface, two implementations, selected at runtime:

- **macOS 26+ with Apple Intelligence available** (`SystemLanguageModel.default.availability == .available`): Foundation Models. A `@Generable` output type constrains the answer to the user's current folder list plus Unsorted. The prompt receives the fetched title, description, and author. On-device, no key, no network.
- **Fallback**: keyword rules over the same metadata. Examples: cooking terms map to Recipes, "episode", "season", or a streaming domain map to Shows.

Rules:

- The category list is user data, not a hardcoded enum. The LLM prompt and the keyword table both read the live folder list.
- Auto-categorisation runs only during enrichment. A manual re-file is final; enrichment never overwrites it.
- Any categorizer failure, guardrail refusal, or a stall over 5 seconds falls back to keyword rules, then to Unsorted. If the target folder was renamed or deleted during enrichment, the bookmark goes to Unsorted.
- Default folders: Recipes, Restaurants, Shows, Articles, Unsorted. The user can add, rename, and delete folders.

## 7. Library and storage

**Library window** (opened from the menu bar popover or its menu):

- Sidebar: folder list with counts, plus an Archive entry at the bottom.
- Main pane: card grid with thumbnail, title, author, source domain, and date. Newest first. No manual reordering in v1.
- Search field: matches title, author, and URL. Search also covers the Archive.
- Double-click opens the link in the default browser. Context menu: mark done, re-file, edit title, copy link, delete.
- Done state: each card has a checkmark action. A done bookmark leaves its folder view and appears in the Archive. The Archive keeps the record ("what was that pasta place again?") and an item can be un-done back to its folder.

**First run**: the library window opens once with an empty state that explains capture ("Copy a link, then click the bookmark icon in the menu bar"), and offers Launch at Login. The app never opens the library uninvited after that.

**Storage**:

- One JSON file in `~/Library/Application Support/Dogear/`, written atomically on every change.
- Thumbnails as image files in a `thumbnails/` subdirectory, named by bookmark id.
- Bookmark record: `id`, `url`, `title`, `author?`, `note?`, `folder`, `source` (tiktok | x | web), `createdAt`, `doneAt?`, `hasThumbnail`, `manuallyFiled` (bool). A bookmark is archived when `doneAt` is set.
- No database. JSON handles thousands of bookmarks. Revisit only if real usage proves otherwise.

## 8. Icons

- All in-app icons are SF Symbols: `bookmark` for the menu bar (`bookmark.fill` when a copied link is detected), `fork.knife` (Recipes), `mappin.and.ellipse` (Restaurants), `tv` (Shows), `doc.text` (Articles), `tray` (Unsorted).
- Custom folders pick from a curated SF Symbol palette.
- The app icon is the bookmark glyph in `assets/logo-glyph.png` centered on a macOS rounded-rect canvas. The glyph matches the MIT-licensed Feather/Lucide bookmark shape, so it is safe to redistribute. Apple's license forbids SF Symbols as app icons, which this avoids.
- No TikTok or X brand logos ship in the repository. Source badges show the domain name or a generic `link` symbol.

## 9. Open source

- License: MIT.
- The repository ships `LICENSE`, `README.md` (what it is, screenshots, install, build instructions), and a short `CONTRIBUTING.md`.
- The repository is public on GitHub from the first release.
- No analytics, no telemetry, no network calls except the metadata fetches the user triggers.

## 10. Error handling

- Network failure or unparseable page: bookmark stays bare and editable. No error dialog on the capture path.
- Invalid clipboard content: the URL field is left empty, nothing else happens.
- Storage write failure: the app surfaces one clear alert, because silent data loss is not acceptable.
- Storage corruption: the app keeps a rotating `.bak` copy of the last good load. When the JSON fails to parse at launch, the app restores from the backup and tells the user. It never silently starts with an empty store.
- LLM unavailable (older OS, Apple Intelligence off, model not downloaded): silent fallback to keyword rules.

## 11. Testing

**Unit tests, run on every PR:**

- URL extraction and scheme rejection (`javascript:`, `file:`, `data:` refused).
- Fetcher routing by domain after redirect resolution.
- OpenGraph parser and oEmbed parser against fixture responses captured from real TikTok and X output, plus malformed and truncated HTML fixtures.
- X title composition (author + truncated tweet text, never `og:title`).
- Keyword categorizer against the accuracy fixture set (section 12).
- Dedupe, including tracking-parameter stripping.
- JSON store: round-trip, kill-during-write atomicity, corrupt-file recovery from `.bak`.
- Done/archive transitions and the manual-refile-is-final rule.

**Offline integration test, run on every PR:** a full save with the network blackholed produces a persisted, editable bare bookmark.

**Live canary tests, scheduled CI only (not on PRs):** one real TikTok oEmbed fetch and one real X OpenGraph fetch. These fail loudly when a platform changes its unauthenticated behavior.

**Not automated:** SwiftUI views, and Foundation Models output. The `Categorizer` interface is covered with a stub; LLM accuracy is a manual run (section 12).

## 12. Benchmarks

The accuracy fixture set is roughly 40 real links, about 8 per default folder, checked into the repository with their expected folders.

| Benchmark | Target | Verification |
| --- | --- | --- |
| Popover open to ready | < 150 ms | manual, Instruments |
| Return pressed to record durably on disk | < 50 ms, independent of network | automated, network blackholed |
| Enrichment visible in library | < 3 s typical, 10 s hard timeout | live canary tests |
| Keyword categorizer accuracy | >= 70% on the fixture set | automated benchmark test |
| LLM categorizer accuracy | >= 85% on the same set | manual run on macOS 26 |
| Library open with 1,000 bookmarks | < 500 ms | automated, generated store |
| Search keystroke to results | < 100 ms | automated, generated store |
| Store load with 5,000 bookmarks | < 200 ms | automated |
| Idle footprint | < 50 MB memory, ~0% CPU | Activity Monitor check per release |
