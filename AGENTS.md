# Snowfall (personal clone) — agent guide

Personal macOS menu-bar app: snow falls over the desktop and piles up on top of windows.
Personal use only, never distributed. Owner is a Swift beginner: keep changes small, explain non-obvious APIs in short comments.

## Build / run
- Swift Package, no Xcode project. Target: macOS 26, Apple Silicon.
- Note: `swift build` fails on this toolchain (linking issue with PackageDescription manifest API).
- Run: `./run.sh` (builds and opens `.build/Snowfall.app`; debug: `SNOW_DEBUG=1 ./run.sh`).
- Build only: `./build.sh` (outputs ad-hoc signed `.build/Snowfall.app` with `Info.plist`).
- tools-version 5.9 = Swift 5 language mode. Do NOT switch to Swift 6 mode unless asked.

## Files (Sources/Snowfall)
- main.swift — entry point, accessory activation policy (no Dock icon).
- AppDelegate.swift — transparent click-through overlay NSWindow + SKView + SnowScene per NSScreen (level .statusBar, rebuilt on screen changes), NSStatusItem menu.
- SnowScene.swift — SpriteKit scene: main loop, flake spawn/step/landing, window polling (20 Hz), snow/icicle debris.
- Pile.swift — per-window snow heightmap (columns), slope relaxation, bottom-edge icicles (`Icicle`), occlusion mask, SKShapeNode drawing.
- Flake.swift — pooled flake (SKSpriteNode). Never allocate flakes per frame; use obtainFlake/recycle.
- WindowTracker.swift — CGWindowListCopyWindowInfo → layer-0 windows, front-to-back, converted to per-screen scene coords.
- Config.swift — ALL tunables. Prefer changing values here over changing logic.

## Coordinate rules (important)
- CGWindowList bounds: origin top-left of primary display, y grows down.
- Scene coords: origin bottom-left of each screen, y grows up, 1 unit = 1 pt.
- Per-screen conversion (see WindowTracker):
  - `sceneX = cgX - screen.frame.minX`
  - `sceneY = primaryScreenHeight - cgMaxY - screen.frame.minY`

## Behavior rules
- Window moved / width changed / closed / minimized → its pile is dumped as debris flakes.
- Snow lands and draws only on columns whose top edge is not covered by a window in front.
- No permissions in the MVP: only window bounds are read, never titles or contents.
- AppKit/SpriteKit-touching classes are main-actor.
- Energy saving: Default 30 FPS (configurable to 60 via menu). Rendering and window polling automatically pause when display sleeps or user session becomes inactive (NSWorkspace notifications), resuming on wake/active.
- Launch at login: Menu toggle "로그인 시 실행" uses `SMAppService.mainApp` (requires `.app` bundle with `CFBundleIdentifier = com.codingfl05.snowfall` and `LSUIElement = true`).
- Multi-display: Creates one overlay window and `SnowScene` per `NSScreen`, rebuilding all overlays on `NSApplication.didChangeScreenParametersNotification`.
- Icicles: After a window remains still for `Config.icicleStartDelay` seconds, icicles grow downward from its bottom edge (count scales with window width, hidden where covered by front windows) and snap off into falling debris when the window moves or closes.

## Roadmap
1. [x] Step 1 - Energy saving (30/60 FPS menu, pause on display sleep / session resign active)
2. [x] Step 2 - .app bundle + launch at login (SMAppService)
3. [x] Step 3 - Multi-display: one overlay per NSScreen
4. [x] Step 4 - Icicles under windows left alone
5. Step 5 - Snow on Dock and desktop icons (Accessibility API, needs permission)
6. Step 6 - Snowman
