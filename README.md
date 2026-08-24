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
- Import from Apple Notes, or from a browser bookmarks file. Paste a block of
  text and Dogear saves every link in it.
- Export a folder or the whole library as Markdown.
- Save from any app: select a link, right-click, then Services, Save to Dogear.

## Install

Download `Dogear.app` from the [latest release](https://github.com/freddie-northam/dogear/releases/latest)
and move it to Applications. Dogear needs macOS 15.4 or later.

Each release includes a SHA-256 checksum and GitHub build attestation. Verify
the downloaded ZIP before opening it:

```bash
shasum -a 256 -c Dogear-v1.0.1.zip.sha256
gh attestation verify Dogear-v1.0.1.zip --repo freddie-northam/dogear
```

Releases are built with `Scripts/make-app.sh`, use Hardened Runtime, and carry
an ad-hoc signature. macOS asks you to confirm the first launch: right-click
the app, choose Open, then Open again.

Dogear shows a Dock icon by default. For a menu bar only app, turn off
"Show icon in Dock" in Settings.

## Build from source

You need Xcode 16 or later. Nothing else.

```bash
git clone https://github.com/freddie-northam/dogear
cd dogear
swift test              # offline suite; live canaries are skipped
Scripts/make-app.sh     # builds build/Dogear.app
open build/Dogear.app
```

## Privacy

Dogear stores everything in one local JSON file, with a backup beside it.
The app makes network requests only to fetch metadata for links you save.
It checks the clipboard's shape without a content read, and reads the
content only when the clipboard holds a link. Import from Notes and Save to
Dogear read only what you choose to import or select.

## License

MIT. See [LICENSE](LICENSE).
