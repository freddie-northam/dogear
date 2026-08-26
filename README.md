<p align="center">
  <img src="assets/app-icon.png" width="128" alt="Dogear app icon">
</p>

<h1 align="center">Dogear</h1>

<p align="center">
  <b>Save links now. Come back to them when you have time.</b><br>
  A small macOS app for the recipes, restaurants, shows, music, and articles you save from TikTok, X, and the web.
</p>

<p align="center">
  <a href="https://github.com/freddie-northam/dogear/releases/latest">Download</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="ROADMAP.md">Roadmap</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

## Why Dogear

Links you save for later go to die. A recipe in a note, a restaurant in a
text, a show in a tweet you bookmarked and never opened again. Dogear gives
them one home on your Mac, files them for you, and brings one back each time
you open it.

- **Light.** One megabyte on disk. About 13 MB of memory in the menu bar.
  Zero third-party dependencies, only Apple's frameworks.
- **Private.** Your library is one JSON file on your Mac. No account, no
  server, no telemetry.
- **Calm.** No notifications, ever. You open Dogear; it never interrupts you.

## How it works

1. Copy a link. In TikTok or X on your iPhone, use Share, then Copy Link.
   Universal Clipboard carries it to your Mac.
2. The bookmark icon in the menu bar fills when a link is ready.
3. Click the icon and press Return. Done.

Set a shortcut in Settings and step 2 goes away: press it in any app and
Dogear saves the copied link, with a tick in the menu bar to say so.

Dogear fetches the title, the author, and a thumbnail, and files the link into
a folder: Recipes, Restaurants, Shows, Music, or Articles. On macOS 26 with
Apple Intelligence, an on-device model picks the folder. On earlier systems,
keyword rules pick it. Move any bookmark yourself and Dogear never moves it
again.

When you cook the recipe or watch the show, mark it done. It moves to the
Archive, which stays searchable. Undo with Command Z.

## The library

- Grid view or list view. Sort by last saved, oldest first, title, or site.
- Your own folders, in the order you drag them into.
- Favourites, notes, and a QR code to open any link on your phone.
- Places: restaurants and hotels that live in a note with no link. Paste
  "City ~ Name" lines, check what the map found, and each one becomes a card
  with its address and a map of its corner. A click opens it in Maps.
- Import from Apple Notes, or from a browser bookmarks file. Paste a block of
  text and Dogear saves every link in it.
- Export as Markdown, or as a bookmarks file every browser reads.
- Save from any app: select a link, right-click, then Services, Save to Dogear.
- Find a saved link from Spotlight, without opening Dogear.
- Save Links to Dogear, an action for Shortcuts.

## Install

Download `Dogear.app` from the [latest release](https://github.com/freddie-northam/dogear/releases/latest)
and move it to Applications. Dogear needs macOS 15.4 or later.

Releases are built with `Scripts/make-app.sh` and carry an ad-hoc signature,
so macOS asks you to confirm the first launch: right-click the app, choose
Open, then Open again.

Dogear shows a Dock icon by default. For a menu bar only app, turn off
"Show icon in Dock" in Settings.

## Build from source

You need Xcode 16 or later. Nothing else.

```bash
git clone https://github.com/freddie-northam/dogear
cd dogear
swift test              # the whole suite, all offline
Scripts/make-app.sh     # builds build/Dogear.app
open build/Dogear.app
```

## Privacy

Dogear stores everything in one local JSON file, with a backup beside it.
There is no account, no server, and no telemetry.

The app goes out to the network only for things you start:
it fetches the title, author, and thumbnail for a link you save, and for a
place you add it sends the text you pasted to Apple's map service to find
the place, then draws a small map of it. Nothing else leaves your Mac.

Dogear checks the clipboard's shape without a content read, and reads the
content only when the clipboard holds a link. Import from Notes and Save to
Dogear read only what you choose to import or select. Spotlight search is a
list the system keeps on this Mac; one setting turns it off and removes it.

## License

MIT. See [LICENSE](LICENSE).
