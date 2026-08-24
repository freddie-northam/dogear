# Plan 015: Add a Save to Dogear entry to the macOS Services menu

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report, do not improvise.
> Your reviewer maintains `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat fd1e79d..HEAD -- Sources/Dogear/DogearApp.swift Scripts/make-app.sh`
> On any change since `fd1e79d`, compare the "Current state" excerpts against
> the live code; on a mismatch, STOP.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `fd1e79d`, 2026-08-24

## Why this matters

Every capture route in Dogear funnels through the clipboard: the copy step is the whole friction on the Mac. A feasibility spike compared a Share Extension (`.appex`) against an `NSServices` entry and concluded the appex path is blocked for a script-built, ad-hoc-signed app (sandbox requirement, nested signing, no app-group data path without a paid team), while Services costs a plist block plus ~25 lines and uses machinery the app already has. This plan ships the Services path: select a link (or any text containing links) in any app, right-click, Services, Save to Dogear. It stays strictly user-initiated and inherits the single capture gate (scheme filter, dedupe, enrichment) for free.

## Current state

Relevant files:

- `Sources/Dogear/DogearApp.swift`, `@main` SwiftUI App; `init()` already reaches into AppKit (excerpt below). `AppModel` is created as a `@StateObject`; there is no shared/singleton accessor, and `AppModel.capture(text:)` is `@MainActor` (the whole class is `@MainActor`) and returns a `CaptureResult` (`new`/`total` counts).
- `Scripts/make-app.sh`, builds the bundle; the Info.plist heredoc contains `LSUIElement` at line 31 and `NSAppleEventsUsageDescription` at line 32. `CFBundleExecutable` is `Dogear`.

`DogearApp.swift` excerpt (lines 25-36):

```swift
@main
struct DogearApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var clipboard = ClipboardWatcher()
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @Environment(\.openWindow) private var openWindow

    init() {
        // No dock icon: menu bar app. Replaces LSUIElement when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
```

Conventions: fewest files (a small new file `Sources/Dogear/ServiceProvider.swift` is acceptable and preferred over growing DogearApp.swift); no em dashes; Conventional Commits, no AI attribution; STE for any user-visible string; UI stays untested (no automated test possible for Services delivery, verification is build plus a scripted plist check).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | Build complete |
| Full tests | `swift test` | exit 0, zero warnings |
| Bundle | `Scripts/make-app.sh` | ends with "Built build/Dogear.app" |
| Plist check | `plutil -extract NSServices json -o - build/Dogear.app/Contents/Info.plist` | JSON array with one service dict |

## Scope

**In scope**:

- `Scripts/make-app.sh` (NSServices block in the Info.plist heredoc)
- `Sources/Dogear/DogearApp.swift` (wire the provider)
- Create: `Sources/Dogear/ServiceProvider.swift`

**Out of scope**: README (a later docs plan mentions the feature); `AppModel.swift` (no singleton, pass the instance); any `.appex`/extension work; `CFBundleURLTypes`.

## Git workflow

- Commit in the worktree; one `feat:` Conventional Commit. Do NOT push.

## Steps

### Step 1: ServiceProvider

Create `Sources/Dogear/ServiceProvider.swift`:

```swift
import AppKit
import DogearKit

/// Receives the Save to Dogear service. NSApp.servicesProvider does not
/// retain its provider, so DogearApp holds the strong reference.
final class ServiceProvider: NSObject {
    private let capture: @MainActor (String) -> Void

    init(capture: @escaping @MainActor (String) -> Void) {
        self.capture = capture
    }

    @objc func saveToDogear(_ pasteboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }
        let capture = capture
        Task { @MainActor in capture(text) }
    }
}
```

**Verify**: `swift build` → Build complete.

### Step 2: Wire it in DogearApp

In `DogearApp`, hold the provider strongly and register it. `@StateObject`'s wrapped value must not be touched in `init`, so register lazily instead: add a private `@State private var serviceProvider: ServiceProvider?` and, in the existing MenuBarExtra content `.onAppear` block (which already runs the first-launch logic), if `serviceProvider == nil`, create it with `{ [weak model] text in _ = model?.capture(text: text) }`-style closure capturing the model (`model` is a `@StateObject`; capturing the object reference in the closure is fine), assign it to the state var, and set `NSApp.servicesProvider = provider`. Then call `NSUpdateDynamicServices()` once so a rebuilt bundle refreshes registration during development.

Note: `.onAppear` on MenuBarExtra `.window`-style content fires on first popover open, not at launch. That is acceptable for v1 of this feature (the service auto-launches the app if not running, and macOS delivers the service message after launch; when the app was launched by the service itself, AppKit sends the service request after the run loop starts, so registration must happen without user interaction in that path). To cover the launched-by-service path, ALSO register from `DogearApp.init()` is impossible (no model yet), instead put the registration in `AppModel.init` guarded to main actor? NO, out of scope. The correct in-scope shape: register in a `.task` modifier on the MenuBarExtra LABEL view (the label renders at launch, unlike the window content). Attach `.task { registerServiceProviderIfNeeded() }` to the label's `Image`, with the register function defined on `DogearApp` doing the nil-check/create/assign described above.

**Verify**: `swift build` → Build complete; `swift test` → all pass, zero warnings.

### Step 3: NSServices in the plist

In `Scripts/make-app.sh`'s Info.plist heredoc, after the `LSUIElement` line, add:

```xml
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Save to Dogear</string></dict>
            <key>NSMessage</key><string>saveToDogear</string>
            <key>NSPortName</key><string>Dogear</string>
            <key>NSSendTypes</key>
            <array><string>public.url</string><string>public.utf8-plain-text</string></array>
        </dict>
    </array>
```

`NSPortName` must equal `CFBundleExecutable` (it is `Dogear`; confirm in the heredoc).

**Verify**: `bash -n Scripts/make-app.sh` → exit 0. `Scripts/make-app.sh` → "Built build/Dogear.app". `plutil -extract NSServices json -o - build/Dogear.app/Contents/Info.plist` → JSON containing `"NSMessage" : "saveToDogear"` (plutil output formatting may vary; presence of the key is the check).

## Test plan

No automated test can exercise Services delivery. The scripted gates are the build, the full suite (unchanged), and the plist extraction. Manual QA (reviewer/user, not the executor): copy app to /Applications, `lsregister -f`, select a link in Safari, right-click → Services → Save to Dogear, confirm it lands in the library.

## Done criteria

- [ ] `swift test` exits 0, zero warnings.
- [ ] `Scripts/make-app.sh` succeeds; `plutil -extract NSServices json -o - build/Dogear.app/Contents/Info.plist` shows the service with `saveToDogear`.
- [ ] `grep -n "servicesProvider" Sources/Dogear/DogearApp.swift` shows the assignment; `grep -n "NSUpdateDynamicServices" Sources/Dogear/` shows one call.
- [ ] `git status --porcelain` shows only in-scope files (build/ is gitignored).

## STOP conditions

- Excerpt mismatch (drift).
- The `.task`-on-label approach fails to compile against MenuBarExtra's label builder (report the compiler error; do not move registration into AppModel).
- `plutil` shows the heredoc produced invalid plist XML after one fix attempt.

## Maintenance notes

- If the launched-by-service path proves unreliable in manual QA (service invoked while app not running, bookmark not saved), the follow-up is registering from an `NSApplicationDelegateAdaptor`, a deliberate scope cut here.
- The Services menu item may need enabling under System Settings, Keyboard, Keyboard Shortcuts, Services; the publication docs plan should mention it.
- A future "Save current Safari tab" AppleScript action is adjacent (same Automation plumbing as Notes import) and was deliberately not bundled into this plan.
