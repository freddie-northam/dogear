# Stash: design specification

Date: 2026-08-23
Status: approved design, ready for implementation planning
Working name: Stash (rename is a one-line change)

## 1. Purpose

Stash is a small open source macOS app. It captures links from TikTok, X, and the web, and it files them into folders such as Recipes, Restaurants, Shows, and Articles. The app must stay clean and lightweight: native code, no server, no accounts, no third-party dependencies.

## 2. Scope

### In scope for v1

- Menu bar app with a quick-add popover.
- Library window with folders, thumbnails, and search.
- Automatic metadata fetch (title, author, thumbnail) per site.
- Automatic categorisation: on-device LLM on macOS 26+, keyword rules otherwise.
- Manual re-file, edit, and delete.
- Local JSON storage.

### Out of scope for v1

- Global hotkey.
- Background clipboard watcher (the popover reads the clipboard only when it opens).
- iOS capture, browser extension, sync, and export.
- Instagram support beyond the generic fallback (Instagram requires login for metadata).

## 3. Platform and stack

- Swift + SwiftUI, `MenuBarExtra` for the menu bar presence.
- Deployment target: macOS 15. The LLM path activates on macOS 26+ at runtime.
- Zero third-party packages.
- Xcode project in a public GitHub repository. Later releases ship as a notarized DMG.

## 4. Capture flow

1. The user clicks the menu bar icon. A popover opens.
2. If the clipboard contains a URL, the URL field is pre-filled. Universal Clipboard carries links copied on iPhone.
3. The user presses Return. The app saves the bookmark immediately.

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

## 6. Categorisation

One `Categorizer` interface, two implementations, selected at runtime:

- **macOS 26+ with Apple Intelligence available** (`SystemLanguageModel.default.availability == .available`): Foundation Models. A `@Generable` output type constrains the answer to the user's current folder list plus Unsorted. The prompt receives the fetched title, description, and author. On-device, no key, no network.
- **Fallback**: keyword rules over the same metadata. Examples: cooking terms map to Recipes, "episode", "season", or a streaming domain map to Shows.

Rules:

- The category list is user data, not a hardcoded enum. The LLM prompt and the keyword table both read the live folder list.
- Auto-categorisation runs only during enrichment. A manual re-file is final; enrichment never overwrites it.
- Default folders: Recipes, Restaurants, Shows, Articles, Unsorted. The user can add, rename, and delete folders.

## 7. Library and storage

**Library window** (opened from the menu bar popover or its menu):

- Sidebar: folder list with counts.
- Main pane: card grid with thumbnail, title, author, source domain, and date.
- Search field: matches title, author, and URL.
- Double-click opens the link in the default browser. Context menu: re-file, edit title, copy link, delete.

**Storage**:

- One JSON file in `~/Library/Application Support/Stash/`, written atomically on every change.
- Thumbnails as image files in a `thumbnails/` subdirectory, named by bookmark id.
- Bookmark record: `id`, `url`, `title`, `author?`, `note?`, `folder`, `source` (tiktok | x | web), `createdAt`, `hasThumbnail`, `manuallyFiled` (bool).
- No database. JSON handles thousands of bookmarks. Revisit only if real usage proves otherwise.

## 8. Icons

- All in-app icons are SF Symbols: `bookmark` for the menu bar, `fork.knife` (Recipes), `mappin.and.ellipse` (Restaurants), `tv` (Shows), `doc.text` (Articles), `tray` (Unsorted).
- Custom folders pick from a curated SF Symbol palette.
- The app icon is one piece of custom artwork (Apple's license forbids SF Symbols as app icons).
- No TikTok or X brand logos ship in the repository. Source badges show the domain name or a generic `link` symbol.

## 9. Error handling

- Network failure or unparseable page: bookmark stays bare and editable. No error dialog on the capture path.
- Invalid clipboard content: the URL field is left empty, nothing else happens.
- Storage write failure: the app surfaces one clear alert, because silent data loss is not acceptable.
- LLM unavailable (older OS, Apple Intelligence off, model not downloaded): silent fallback to keyword rules.

## 10. Testing

- Unit tests for OpenGraph parsing and oEmbed parsing against fixture responses captured from real TikTok and X output.
- Unit tests for the keyword categorizer.
- Round-trip test for the JSON store, including atomic-write behavior.
- The Foundation Models path is behind the `Categorizer` interface; tests cover the interface with a stub, not the model.
- UI is thin and stays untested in v1.
