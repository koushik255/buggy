# Buggy

Buggy is a macOS menu-bar app for clipping a bug reproduction. You record while you reproduce the bug. Buggy does not save a video. It keeps a small set of JPEG frames and writes a `clip.md` note you can paste into an LLM chat with the images.

## Clip a bug

1. Open Buggy. It lives in the menu bar as a ladybug and does not show a Dock icon.
2. Choose **Ready to Clip**, or press **Control-Option-B**.
3. Reproduce the bug in whatever app you are testing.
4. Choose **Clip**, or press **Control-Option-B** again.
5. Buggy writes a timestamped folder and asks you to reveal it in Finder or copy the markdown.

Clips are saved in `~/Documents/Buggy Clips/<yyyy-MM-dd_HH-mm-ss>/`:

```text
frame-01.jpg
frame-02.jpg
frame-03.jpg
clip.md
```

The same menu items stay available afterward: **Reveal Last Clip in Finder**, **Copy Markdown**, and **Open Clips Folder**.

Quit while a clip is still recording discards that clip. Recording also stops on its own after 90 seconds (configurable).

## What gets kept

Frames are sampled in memory at about 4 per second. Nothing is written as a movie. After you stop, Buggy keeps:

- the opening frame
- a frame when the screen actually changes
- a frame around each mouse click and key press
- the closing frame, when it differs from the last frame already kept

Near-duplicate screen changes are dropped. Clicks and keys are kept even when the pixels barely change, because the event is the point of the frame. The total is capped (16 by default, menu choices 8, 12, 16, 20, 24). If the cap is hit, clicks and keys are kept ahead of ordinary screen changes, spread across the clip. The largest visual changes fill any slots that remain.

Each kept frame is a JPEG whose longest side is at most 1280 pixels. Clicks are drawn as a red ring so the model can see where the pointer went. `clip.md` lists every frame with its timestamp and why it was kept.

```markdown
# Buggy clip

- Started: 2026-10-17 18:30:04
- Duration: 4.20s
- Capture: Built-in Display
- Image size: 1280x720 pixels, JPEG, longest side at most 1280px
- Frames: 3 of up to 16
- Coordinates: pixels in the image, origin at the top-left
- Input: clicks and keys recorded

Attach these images, in order, with this note.

## Frames

1. `frame-01.jpg` — 0.00s — session start
2. `frame-02.jpg` — 1.20s — click left at (412, 220)
3. `frame-03.jpg` — 4.20s — screen change (delta 0.21); session end
```

A `delta` of `0` is identical and `1` is as different as black and white. It is the mean absolute difference of a 32×18 grayscale downsample.

## Capture target

The **Capture** submenu lists displays and on-screen windows. The choice applies to the next clip.

- **Display** records that whole screen, including the cursor.
- **Window** records one window. Clicks that land outside it do not get a ring. The note says `key click outside capture` for that moment, and a frame is still kept.

Window and display names appear after Screen Recording permission is granted. Open the menu again if the list is empty.

## Requirements

- macOS 13 or later
- Xcode 15 or later, or a Swift 5.9+ toolchain
- Screen Recording permission (required)
- Accessibility permission (optional, for clicks and keys)

`swift test` also runs on Linux. The menu-bar app itself only runs on macOS.

## Build, test, and run

From the repository root:

```bash
swift test
```

On a Mac, build an app bundle. Permissions are granted to the bundle, so this is the copy to open:

```bash
./Scripts/make-app.sh
open dist/Buggy.app
```

The script builds the release binary, wraps it in `dist/Buggy.app`, and ad-hoc signs it. You can also open `Package.swift` in Xcode 15+ and run the **Buggy** scheme. A bare `swift run` binary works for a smoke test, but macOS will not remember Screen Recording permission for it across rebuilds. Use `dist/Buggy.app`.

The first time you open an ad-hoc signed app, Gatekeeper may refuse it. Right-click `Buggy.app`, choose **Open**, and confirm.

`make app` is the same as the script. `make test` and `make build` call Swift Package Manager.

## Permissions

Start a clip once. Buggy asks for what it needs.

**Screen Recording** is required. macOS shows its own prompt, and Buggy can open System Settings → Privacy & Security → Screen Recording. If you just enabled Buggy, quit and open it again. macOS applies that permission on the next launch. Until it sticks, capture fails or comes back with no frames. The menu shows whether the permission is granted.

**Accessibility** is how Buggy sees clicks and key presses (a listen-only event tap). Without it, clips still work: frames are chosen from screen changes only, and `clip.md` says input was not recorded. The global hotkey does not need Accessibility. It is a Carbon hotkey, Control-Option-B.

An ad-hoc signature changes every time you rebuild, and macOS treats that as a different app. After `./Scripts/make-app.sh`, you may need to toggle Screen Recording and Accessibility off and on for **Buggy**. A stable Developer ID or Apple Development certificate avoids that. This repo does not ship one.

## Defaults

| Setting | Default | Meaning |
| --- | --- | --- |
| Max frames | 16 | Cap, including the opening frame. Hard ceiling 40. |
| Change threshold | 0.06 | Luminance difference that counts as a change. |
| Major change | 0.18 | A change this large is kept immediately. |
| Min change interval | 0.35s | Smaller changes wait at least this long. |
| Duplicate threshold | 0.015 | Screen changes closer than this to the previous kept frame are dropped. |
| Event window | 0.45s | How far a click or key can be from a sample and still attach. |
| Sample rate | 4 fps | Frames held in memory while recording. |
| Max dimension | 1280 px | Longest side of each JPEG. |
| JPEG quality | 0.72 | |
| Max duration | 90s | Recording stops itself. |

The frame cap is in the menu. The other knobs are `UserDefaults` keys, so you can tune the bundled app without rebuilding:

```bash
defaults write app.buggy.mac buggy.changeThreshold -float 0.08
defaults write app.buggy.mac buggy.maxImageDimension -int 960
defaults write app.buggy.mac buggy.sampleFPS -float 3
```

Keys: `buggy.maxFrames`, `buggy.changeThreshold`, `buggy.majorChangeThreshold`, `buggy.duplicateThreshold`, `buggy.minChangeInterval`, `buggy.eventAssociationWindow`, `buggy.sampleFPS`, `buggy.maxImageDimension`, `buggy.jpegQuality`, `buggy.maxDuration`. Values are clamped by `ClipConfig.sanitized()`. A `swift run` binary has no bundle id, so these defaults are not a reliable way to configure that copy. Use `dist/Buggy.app`.

## Project layout

```text
Package.swift
Sources/BuggyCore/          frame selection, diffs, downscale, click marks, clip.md
Sources/Buggy/              macOS menu bar, ScreenCaptureKit, event tap, JPEG export
Tests/BuggyCoreTests/       unit tests, no AppKit
Scripts/make-app.sh         builds dist/Buggy.app on macOS
Resources/Info.plist        bundle id app.buggy.mac, menu-bar agent (LSUIElement)
```

`BuggyCore` is plain Foundation Swift. The app target calls it. On Linux the app target compiles a stub that exits; AppKit and ScreenCaptureKit code is behind `#if os(macOS)` and is not type-checked there.

## What was verified

Verified on this Linux VM (Ubuntu 24.04, Swift 6.2.4):

- `swift test`: 36 tests, all passing. They cover perceptual diff, downscale, click-mark drawing, coordinate mapping, frame selection (changes, clicks, keys, duplicates, the frame cap), config clamping, and the `clip.md` text.
- `swift build`: the package builds. The macOS sources are parsed, but AppKit and ScreenCaptureKit are not compiled or type-checked on Linux.

Not verified, because this environment cannot compile or run AppKit or ScreenCaptureKit:

- `./Scripts/make-app.sh` and launching `Buggy.app`
- Screen Recording and Accessibility prompts
- ScreenCaptureKit display and window capture
- the Control-Option-B hotkey
- JPEG encode/decode and click rings on real frames
- Finder reveal and the pasteboard
- whether click rings land on the right pixel

## What to check on a Mac

1. `swift test` still passes, then `./Scripts/make-app.sh` and `open dist/Buggy.app`.
2. Grant Screen Recording, quit, and reopen. The menu should say **Screen Recording: Granted**, and the Capture submenu should list displays.
3. Grant Accessibility if you want click and key marks.
4. Press Control-Option-B while another app is focused. The menu-bar icon should switch to a record symbol. Press it again.
5. Confirm the folder has numbered JPEGs and a `clip.md` whose lines match the images.
6. Click the top-left of the captured display during a clip. The ring on that frame should be in the top-left, not the bottom-left. Marks use Quartz global coordinates (origin at the top-left of the main display, y down), the same space as `CGEvent.location`, `CGDisplayBounds`, and `kCGWindowBounds`. If a mark is mirrored vertically, that conversion in `InputMonitor` / `QuartzFrames` is the place to fix.
7. Try **Capture → Windows** on a single window and confirm clicks inside the window are marked and clicks outside are not.
8. Copy Markdown, paste it into a chat, and attach the JPEGs in the listed order.
