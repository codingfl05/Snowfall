import AppKit
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct ScreenOverlay {
        let window: NSWindow
        let view: SKView
        let scene: SnowScene
        let tracker: WindowTracker
    }

    private var overlays: [ScreenOverlay] = []
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var intensityItems: [NSMenuItem] = []
    private var fpsItems: [NSMenuItem] = []
    private var currentIntensity: SnowIntensity = .normal
    private var currentFPS: Int = Config.framesPerSecond
    private var isUserPaused = false
    private var isDisplaySleeping = false
    private var isSessionInactive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityTracker.shared.requestPermissionOnce()
        rebuildOverlays()
        setupStatusItem()
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 화면 슬립 / 세션 비활성화 시 렌더링 및 윈도우 폴링 중단, 복귀 시 재개
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - Overlay windows (Multi-display)

    /// 연결된 모든 디스플레이(NSScreen)마다 투명 오버레이 창과 SnowScene을 생성.
    /// 모니터 연결/해제/해상도 변경 시(didChangeScreenParametersNotification) 전체 재생성.
    private func rebuildOverlays() {
        for overlay in overlays {
            overlay.view.isPaused = true
            overlay.view.presentScene(nil)
            overlay.window.orderOut(nil)
            overlay.window.close()
        }
        overlays.removeAll()

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }
        let shouldPause = isUserPaused || isDisplaySleeping || isSessionInactive

        for screen in screens {
            let frame = screen.frame

            let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true          // click-through
            window.level = .statusBar                 // 일반 창과 메뉴바 위에 표시
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false

            let view = SKView(frame: NSRect(origin: .zero, size: frame.size))
            view.allowsTransparency = true
            view.preferredFramesPerSecond = currentFPS
            view.ignoresSiblingOrder = true
            view.autoresizingMask = [.width, .height]

            let tracker = WindowTracker()
            tracker.screenFrame = frame
            tracker.primaryScreenHeight = primaryHeight

            let scene = SnowScene(size: frame.size)
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.intensity = currentIntensity
            scene.tracker = tracker
            view.presentScene(scene)
            view.isPaused = shouldPause

            window.contentView = view
            window.setFrame(frame, display: true)
            if !shouldPause {
                window.orderFrontRegardless()
            }

            overlays.append(ScreenOverlay(window: window, view: view, scene: scene, tracker: tracker))
        }
    }

    @objc private func screenParametersChanged() {
        rebuildOverlays()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "❄︎"

        let menu = NSMenu()
        menu.delegate = self

        let intensityMenu = NSMenu()
        for level in SnowIntensity.allCases {
            let mi = NSMenuItem(title: level.title, action: #selector(selectIntensity(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = level.rawValue
            mi.state = (level == .normal) ? .on : .off
            intensityMenu.addItem(mi)
            intensityItems.append(mi)
        }
        let intensityRoot = NSMenuItem(title: "눈 양", action: nil, keyEquivalent: "")
        intensityRoot.submenu = intensityMenu
        menu.addItem(intensityRoot)

        let fpsMenu = NSMenu()
        for rate in Config.availableFrameRates {
            let mi = NSMenuItem(title: "\(rate)", action: #selector(selectFPS(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = rate
            mi.state = (rate == Config.framesPerSecond) ? .on : .off
            fpsMenu.addItem(mi)
            fpsItems.append(mi)
        }
        let fpsRoot = NSMenuItem(title: "FPS", action: nil, keyEquivalent: "")
        fpsRoot.submenu = fpsMenu
        menu.addItem(fpsRoot)

        let pause = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let shake = NSMenuItem(title: "쌓인 눈 털기", action: #selector(shakeOffSnow), keyEquivalent: "")
        shake.target = self
        menu.addItem(shake)

        let launchAtLogin = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        // 메뉴를 열 때마다 시스템 설정의 로그인 항목 상태와 체크 표시를 동기화
        launchAtLoginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        // SMAppService.mainApp: macOS 13+에서 현재 .app 번들을 로그인 항목에 등록/해제하는 API
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            if Config.debugLogging {
                print("[Snowfall] Launch at login error: \(error)")
            }
        }
        launchAtLoginItem?.state = (service.status == .enabled) ? .on : .off
    }

    @objc private func selectIntensity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = SnowIntensity(rawValue: raw) else { return }
        currentIntensity = level
        for overlay in overlays {
            overlay.scene.intensity = level
        }
        for mi in intensityItems {
            mi.state = (mi.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func selectFPS(_ sender: NSMenuItem) {
        guard let fps = sender.representedObject as? Int else { return }
        currentFPS = fps
        for overlay in overlays {
            overlay.view.preferredFramesPerSecond = fps
        }
        for mi in fpsItems {
            mi.state = (mi.representedObject as? Int) == fps ? .on : .off
        }
    }

    @objc private func togglePause() {
        isUserPaused.toggle()
        pauseItem?.title = isUserPaused ? "다시 시작" : "일시정지"
        updatePauseState()
    }

    @objc private func screensDidSleep() {
        isDisplaySleeping = true
        updatePauseState()
    }

    @objc private func screensDidWake() {
        isDisplaySleeping = false
        updatePauseState()
    }

    @objc private func sessionDidResignActive() {
        isSessionInactive = true
        updatePauseState()
    }

    @objc private func sessionDidBecomeActive() {
        isSessionInactive = false
        updatePauseState()
    }

    private func updatePauseState() {
        let shouldPause = isUserPaused || isDisplaySleeping || isSessionInactive
        for overlay in overlays {
            overlay.view.isPaused = shouldPause
            if shouldPause {
                overlay.window.orderOut(nil)
            } else {
                overlay.window.orderFrontRegardless()
            }
        }
    }

    @objc private func shakeOffSnow() {
        for overlay in overlays {
            overlay.scene.shakeOffAllSnow()
        }
    }
}
