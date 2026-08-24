# Roadmap

This file records product decisions for Dogear: what shipped, what comes
next, and what the team chose to leave out.

## Shipped (v1.x)

- Capture: copy a link, then save it from the menu bar.
- Enrichment: fetch title, author, and thumbnail for a saved link.
- Auto-filing: file a new link into a folder automatically.
- Archive: mark a bookmark done and move it to a searchable archive.
- Pick: the popover shows one saved bookmark that waits for you.
- Multi-link paste: save every link found in a block of pasted text.
- Notes: attach a note to a bookmark.
- Favourites: mark a bookmark as a favourite.
- Markdown export: export bookmarks as a markdown link list.
- Drag in/out: drag a link into Dogear, and drag a bookmark out to another app.
- QR code on cards: show a QR code for a bookmark, so you can open the link
  on your phone.
- Releases: a tag on main builds the app, runs the tests, and publishes a
  zip on GitHub.
- Undo: Delete, Delete Folder, and Mark Done reverse with Command Z.
- Onboarding: a welcome sheet on first launch, and a Help tab in Settings.
- Folder reorder: drag folders into any order. Unsorted stays last.
- Dock icon: on by default, so the app stays reachable when a full menu bar
  hides its item. A click opens the library. A setting turns it off.
- Import from Apple Notes: read your notes locally and save every link found.
  macOS asks for permission first. You pick which folders to read, and a
  second import reads only what changed since the last import.
- List view and sort order: switch between grid and list, and sort by last
  saved, oldest first, title, or site.
- Music folder: a default folder for songs, albums, and playlists.
- Refresh Metadata: re-fetch title, author, and thumbnail for one bookmark.
- File These for Me: run auto-filing over the Unsorted folder on demand.
- Services menu capture: select a link in any app, then choose Services,
  Save to Dogear.
- Browser bookmarks import and Markdown export: import a bookmarks file
  from a browser, and export the library to a Markdown file.

## Next up

Nothing is scheduled. New ideas start as deferred decisions below.

## Deferred by decision

- Nested folders and sidebar dividers: one flat level of folders keeps
  filing simple and the categorizer unambiguous. Revisit if a library
  grows past about 15 folders.

- Notarized releases: gated on an Apple Developer ID; releases are ad-hoc
  signed today.
- Custom-folder symbol palette: a picker for a custom icon per folder.
- First-run launch-at-login offer: an offer to enable launch at login on
  first run.
- iOS Shortcut capture: a Shortcuts action that saves a link from iOS.
- Companion mobile app: a separate iOS app. Far future, not planned now.
- Shared lists via iCloud: share a folder with another person over iCloud.
  The storage format stays sync-friendly today so this stays possible later.

## Principles

- No notifications, ever. You open the app to see a pick. The app never
  pushes one to you.
- Zero third-party dependencies. Dogear uses only Apple's frameworks.
- Local-only data. Dogear stores your library on your Mac, with no server
  and no account.
