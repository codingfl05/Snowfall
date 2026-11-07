# Snowfall (personal clone) — agent guide

Personal macOS menu-bar app: snow falls over the desktop and piles up on top of windows.
Personal use only, never distributed. Owner is a Swift beginner: keep changes small, explain non-obvious APIs in short comments.

## Build / run
- Swift Package, no Xcode project. Target: macOS 26, Apple Silicon.
- Note: `swift build` fails on this toolchain (linking issue with PackageDescription manifest API).
- Run: `./run.sh` (builds and opens `.build/Snowfall.app`; debug: `SNOW_DEBUG=1 ./run.sh`).
- Build only: `./build.sh` (outputs `.build/Snowfall.app` signed with self-signed certificate `"Snowfall Dev"` so Accessibility permission survives rebuilds, falling back to ad-hoc `-s -` with a warning if missing).
- tools-version 5.9 = Swift 5 language mode. Do NOT switch to Swift 6 mode unless asked.

## Files (Sources/Snowfall)
- main.swift — entry point, accessory activation policy (no Dock icon).
- AppDelegate.swift — transparent click-through overlay NSWindow + SKView + SnowScene per NSScreen (level .statusBar, rebuilt on screen changes), NSStatusItem menu.
- SnowScene.swift — SpriteKit scene: main loop, flake spawn/step/landing, window polling (20 Hz), snow/icicle debris.
- Pile.swift — per-surface snow heightmap (columns), slope relaxation, top-border Christmas garland & ornament bulbs (`OrnamentBulb`), bottom-edge icicles (`Icicle`), occlusion mask, SKShapeNode drawing.
- CPUMonitor.swift — samples system-wide CPU usage (`host_statistics` with `HOST_CPU_LOAD_INFO`) at `Config.cpuPollInterval` (1 Hz) to drive ornament bulb blink speed and overload sparkle intensity.
- Flake.swift — pooled flake (SKSpriteNode). Never allocate flakes per frame; use obtainFlake/recycle.
- WindowTracker.swift — shares a single `CGWindowListCopyWindowInfo` snapshot per poll across all screens, detects per-screen fullscreen frontmost apps, and combines Dock items, layer-0 windows, and Finder desktop icons front-to-back in per-screen scene coords.
- AccessibilityTracker.swift — uses `AXUIElement` (`AXIsProcessTrustedWithOptions` once at launch, `AXUIElementSetMessagingTimeout(..., 0.1)` on Dock & Finder app elements) to read Dock item frames (4 Hz, IDs hashed from title only) and Finder desktop icon frames (`Config.axDesktopPollInterval` = 1 Hz); falls back gracefully to windows-only if denied.
- Snowman.swift — animated snowman (`Snowman`) whose two snowballs roll onto the Dock area, stack up, put on a red scarf, wave with a twig arm, and slowly melt away.
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
- Accessibility permission (`AXIsProcessTrustedWithOptions`) is requested once on launch for Dock & Finder desktop icon frames; if denied, the app continues working with windows only without crashing or repeating prompts.
- AppKit/SpriteKit-touching classes are main-actor.
- Energy saving: Default 30 FPS (configurable to 60 via menu). Rendering and window polling automatically pause when display sleeps, user session becomes inactive, Low Power Mode is enabled (`ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`), or on any screen where the frontmost app is fullscreen, resuming automatically when conditions clear.
- Launch at login: Menu toggle "로그인 시 실행" uses `SMAppService.mainApp` (requires `.app` bundle with `CFBundleIdentifier = com.codingfl05.snowfall` and `LSUIElement = true`).
- Multi-display: Creates one overlay window and `SnowScene` per `NSScreen`, rebuilding all overlays on `NSApplication.didChangeScreenParametersNotification`, and shares a single `CGWindowListCopyWindowInfo` snapshot per poll across all screens' trackers.
- Icicles: After a window remains still for `Config.icicleStartDelay` seconds, icicles grow downward from its bottom edge (count scales with window width, hidden where covered by front windows) and snap off into falling debris when the window moves or closes.
- Dock & desktop icons: Treated as `Pile` surfaces (`SurfaceKind.dockItem` in front of windows, `SurfaceKind.desktopIcon` behind windows so windows occlude desktop icons, with top-offset and dome taper so snow sits naturally on folder icons). Stage Manager strip thumbnails and system overlay windows (`WindowManager`, `Dock`, `Control Center`) are excluded from window tracking.
- Snowman: Periodically (`Config.snowmanFirstDelay` then `Config.snowmanIntervalRange`), two snowballs roll onto the Dock area, stack into a snowman with a red scarf and carrot nose, wave, and melt away. Can be toggled on/off via the "눈사람 표시" menu item (persisted in `UserDefaults`, immediately destroying and deallocating nodes when turned off).
- Christmas Ornaments & CPU Load Lights: Along each normal window's top border (starting right after the macOS left traffic-light buttons to the top-right edge), a festive pine-green garland cord drapes in catenary swags with hanging glossy bauble ornaments and fairy light bulbs. `CPUMonitor` measures real-time system CPU load via Mach `host_statistics(HOST_CPU_LOAD_INFO)`: bulbs breathe slowly when idle (`Config.ornamentMinBlinkSpeed`) and blink/sparkle rapidly as CPU load or system overload increases (`Config.ornamentMaxBlinkSpeed`). Covered segments hide automatically when occluded by front windows, and the feature can be toggled via the "크리스마스 장식" menu item.

## Roadmap
1. [x] Step 1 - Energy saving (30/60 FPS menu, pause on display sleep / session resign active)
2. [x] Step 2 - .app bundle + launch at login (SMAppService)
3. [x] Step 3 - Multi-display: one overlay per NSScreen
4. [x] Step 4 - Icicles under windows left alone
5. [x] Step 5 - Snow on Dock and desktop icons (Accessibility API, needs permission)
6. [x] Step 6 - Snowman
