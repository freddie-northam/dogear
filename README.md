# Dogear

<img src="assets/logo-glyph.png" width="80" align="right" alt="Dogear logo">

Dogear is a small macOS app that lives in your menu bar and your Dock. It
saves links from TikTok, X, and the web, and files them into folders:
recipes to make, restaurants to visit, shows to watch, music to hear,
articles to read.

Click the Dock icon to open the library. If you prefer a menu bar only
app, turn off "Show icon in Dock" in Settings.

## How it works

On first launch, Dogear shows a short welcome and offers to import your
links. Settings, then Help, shows the same guide at any time.

1. Copy a link. On your iPhone too: Universal Clipboard carries it to your Mac.
2. The bookmark icon in the menu bar fills when a link is on the clipboard.
3. Click the icon and press Return. Done.

Dogear fetches the title, author, and thumbnail, and files the link into the
right folder. On macOS 26 with Apple Intelligence, an on-device model picks
the folder. On earlier systems, keyword rules pick it. You can always move a
bookmark yourself.

When you cook the recipe or watch the show, mark the bookmark done. It moves
to the Archive, which stays searchable.

## Save from TikTok and X

In TikTok or X on your iPhone, use Share, then Copy Link. Universal
Clipboard carries the link to your Mac. Dogear fetches the caption, the
author, and a thumbnail, and files the link.

## Import your links from Apple Notes

1. Open the library window.
2. Click the plus button and choose Import from Notes.
3. Click Import.

macOS asks for permission one time. Dogear reads your notes on this Mac and
saves every link it finds. You can also paste a block of text with many
links into the popover. Dogear saves every link it finds in the text.

## In the library

- Make your own folders, and drag folders into the order you want.
- Switch between grid view and list view.
- Sort by last saved, oldest first, title, or site.
- Star a bookmark as a favourite.
- Add a note to a bookmark.
- Show a QR code for a bookmark, so you can open the link on your phone.
- Copy a bookmark, or a whole folder, as Markdown.
- Import a browser bookmarks file.
- Export the library to a Markdown file.
- Click File These for Me to run auto-filing over the Unsorted folder.

## From any app

Select a link anywhere, then choose Services, Save to Dogear from the
right-click menu. If you do not see the option, enable it in System
Settings, Keyboard, Keyboard Shortcuts, Services.

## Install

Download `Dogear.app` from the latest GitHub release and move it to
Applications. Releases are built with `Scripts/make-app.sh` and signed with
an ad-hoc signature. macOS may ask you to confirm the first launch. Or build
from source:

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
read, and reads the content only when the clipboard holds a link. Import
from Notes and Save to Dogear read only what you choose to import or
select.

## License

MIT. See [LICENSE](LICENSE).

See ROADMAP.md for what comes next.
