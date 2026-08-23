# Dogear

<img src="assets/logo-glyph.png" width="80" align="right" alt="Dogear logo">

Dogear is a small macOS menu bar app. It saves links from TikTok, X, and the
web, and files them into folders: recipes to make, restaurants to visit,
shows to watch, articles to read.

## How it works

1. Copy a link. On your iPhone too: Universal Clipboard carries it to your Mac.
2. The bookmark icon in the menu bar fills when a link is on the clipboard.
3. Click the icon and press Return. Done.

Dogear fetches the title, author, and thumbnail, and files the link into the
right folder. On macOS 26 with Apple Intelligence, an on-device model picks
the folder. On earlier systems, keyword rules pick it. You can always move a
bookmark yourself.

When you cook the recipe or watch the show, mark the bookmark done. It moves
to the Archive, which stays searchable.

## Move your links from Apple Notes

1. Open the note that holds your links.
2. Select all the text and copy it.
3. Click the Dogear icon in the menu bar.
4. Press Save.

Dogear saves every link it finds in the text and files each one into the
right folder.

## Install

Download `Dogear.app` from the latest GitHub release and move it to
Applications. Or build from source:

```bash
git clone https://github.com/northamf/dogear
cd dogear
Scripts/make-app.sh
open build/Dogear.app
```

Requires macOS 15.4 or later.

## Privacy

Dogear stores everything in one local JSON file. There is no server, no
account, no telemetry. The app makes network requests only to fetch metadata
for links you save. Dogear checks the clipboard's shape without a content
read, and reads the content only when the clipboard holds a link.

## License

MIT. See [LICENSE](LICENSE).
