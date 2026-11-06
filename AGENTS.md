# Snowfall (personal clone) — agent guide

Personal macOS menu-bar app: snow falls over the desktop and piles up on top of windows.
Personal use only, never distributed. Owner is a Swift beginner: keep changes small, explain non-obvious APIs in short comments.

## Build / run
- Swift Package, no Xcode project. Target: macOS 26, Apple Silicon.
- Note: `swift build` fails on this toolchain (linking issue with PackageDescription manifest API).
- Run: `./run.sh` (debug: `SNOW_DEBUG=1 ./run.sh`).
- Build only: `./build.sh` (outputs to `.build/Snowfall`).
- tools-version 5.9 = Swift 5 language mode. Do NOT switch to Swift 6 mode unless asked.

## Files (Sources/Snowfall)
- main.swift — entry point, accessory activation policy (no Dock icon).
- AppDelegate.swift — transparent click-through overlay NSWindow (level .statusBar, primary screen only), SKView, NSStatusItem menu.
- SnowScene.swift — SpriteKit scene: main loop, flake spawn/step/landing, window polling (20 Hz), debris.
- Pile.swift — per-window snow heightmap (columns), slope relaxation, occlusion mask, SKShapeNode drawing.
- Flake.swift — pooled flake (SKSpriteNode). Never allocate flakes per frame; use obtainFlake/recycle.
- WindowTracker.swift — CGWindowListCopyWindowInfo → layer-0 windows, front-to-back, converted to scene coords.
- Config.swift — ALL tunables. Prefer changing values here over changing logic.

## Coordinate rules (important)
- CGWindowList bounds: origin top-left of primary display, y grows down.
- Scene coords: origin bottom-left of primary screen, y grows up, 1 unit = 1 pt.
- sceneY = screenHeight - cgMaxY (see WindowTracker).

## Behavior rules
- Window moved / width changed / closed / minimized → its pile is dumped as debris flakes.
- Snow lands and draws only on columns whose top edge is not covered by a window in front.
- No permissions in the MVP: only window bounds are read, never titles or contents.
- AppKit/SpriteKit-touching classes are main-actor.
- Energy saving: Default 30 FPS (configurable to 60 via menu). Rendering and window polling automatically pause when display sleeps or user session becomes inactive (NSWorkspace notifications), resuming on wake/active.

## Roadmap
1. [x] Step 1 - Energy saving (30/60 FPS menu, pause on display sleep / session resign active)
2. Step 2 - .app bundle + launch at login (SMAppService)
3. Step 3 - Multi-display: one overlay per NSScreen
4. Step 4 - Icicles under windows left alone
5. Step 5 - Snow on Dock and desktop icons (Accessibility API, needs permission)
6. Step 6 - Snowman
