# Roadmap

This file records product decisions for Dogear: what shipped, what comes
next, and what the team chose to leave out.

## Shipped (v1.x)

- Capture: copy a link, then save it from the menu bar.
- Enrichment: fetch title, author, and thumbnail for a saved link.
- Auto-filing: file a new link into a folder automatically.
- Archive: mark a bookmark done and move it to a searchable archive.
- Resurfacing pick: show one saved bookmark at random.
- Multi-link paste: save every link found in a block of pasted text.
- Notes: attach a note to a bookmark.
- Favourites: mark a bookmark as a favourite.
- Markdown export: export bookmarks as a markdown link list.
- Drag in/out: drag a link into Dogear, and drag a bookmark out to another app.
- QR code on cards: show a QR code for a bookmark, so you can open the link
  on your phone.
- Import from Apple Notes: read your notes locally and save every link found.
  macOS asks for permission first.

## Next up

Nothing is scheduled. New ideas start as deferred decisions below.

## Deferred by decision

- Custom-folder symbol palette: a picker for a custom icon per folder.
- First-run launch-at-login offer: an offer to enable launch at login on
  first run.
- iOS Shortcut capture: a Shortcuts action that saves a link from iOS.
- Companion mobile app: a separate iOS app. Far future, not planned now.
- Shared lists via iCloud: share a folder with another person over iCloud.
  The storage format stays sync-friendly today so this stays possible later.

## Principles

- No notifications, ever. Resurfacing is pull-based: you open the app to see
  a pick, the app never pushes one to you.
- Zero third-party dependencies. Dogear uses only Apple's frameworks.
- Local-only data. Dogear stores your library on your Mac, with no server
  and no account.
