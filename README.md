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
  server, no telemetry. One feature can send text off your Mac, and it is
  off until you turn it on: see [Folder suggestions](#folder-suggestions).
- **Calm.** No notifications, ever. You open Dogear; it never interrupts you.

## Folder suggestions

Dogear files a link by matching words in its title, and it can only file into
a folder you already have. A library full of things your folders have no name
for stays in Unsorted, and nothing tells you why.

Folder suggestions fix that. Dogear reads the links waiting in Unsorted and
shows you folders worth making, each with the number of links that would move
into it. You choose which to make, and nothing moves until you accept.

On its own Dogear can only offer folders it already knows how to fill, such
as Developer for a saved repository. Turn the setting below on and it asks a
model to name folders from your links themselves, which can propose one
Dogear has never heard of.

**That setting sends the titles of your waiting bookmarks off your Mac.** It
is off by default, Dogear never turns it on for you, and the suggestions
above keep working without it.

It uses a command line tool you already have and are already signed in to,
such as Claude Code or Codex. Dogear does not bundle a model, does not ask
for an API key, and has no account of its own. Your titles go to that tool
and to whichever provider you signed in to, under your own subscription.

To turn it on, open Settings and give Dogear the full path to the command,
for example `/opt/homebrew/bin/codex`. A full path is needed because an app
opened from the Finder cannot see the same `PATH` your terminal does. Use
Test to confirm the command answers before you rely on it.

Everything else in Dogear stays on your Mac whether this is on or off.

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
swift test              # 155 tests, all offline
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
