import AppKit
import IOKit.ps
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct ScreenOverlay {
        let window: NSWindow
        let view: SKView
        let scene: SnowScene
        let tracker: WindowTracker
        var isFullscreenPaused: Bool = false
    }

    private var overlays: [ScreenOverlay] = []
    private var fullscreenTimer: Timer?
    private var powerRunLoopSource: CFRunLoopSource?
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var snowItem: NSMenuItem?
    private var intensityRootItem: NSMenuItem?
    private var shakeItem: NSMenuItem?
    private var snowmanItem: NSMenuItem?
    private var ornamentsItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var intensityItems: [NSMenuItem] = []
    private var fpsItems: [NSMenuItem] = []
    private var batterySaverItems: [NSMenuItem] = []
    private var currentIntensity: SnowIntensity = .normal
    private var currentFPS: Int = Config.framesPerSecond
    private var batterySaverMode: BatterySaverMode = {
        if let raw = UserDefaults.standard.string(forKey: "batterySaverMode"),
           let mode = BatterySaverMode(rawValue: raw) {
            return mode
        }
        return Config.defaultBatterySaverMode
    }()
    private var isOnBattery: Bool = AppDelegate.checkOnBatteryPower()
    private var isSnowEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "snowEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "snowEnabled")
        }
        return Config.defaultSnowEnabled
    }()
    private var isSnowmanEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "snowmanEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "snowmanEnabled")
        }
        return Config.defaultSnowmanEnabled
    }()
    private var isOrnamentsEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "ornamentsEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "ornamentsEnabled")
        }
        return Config.defaultOrnamentsEnabled
    }()
    private var isUserPaused = false
    private var isDisplaySleeping = false
    private var isSessionInactive = false
    private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var isGloballyPaused: Bool {
        isUserPaused
            || isDisplaySleeping
            || isSessionInactive
            || isLowPowerMode
            || (!isSnowEnabled && !isOrnamentsEnabled)
    }

    private var isBatterySaverActive: Bool {
        switch batterySaverMode {
        case .off: return false
        case .auto: return isOnBattery
        case .always: return true
        }
    }

    private var effectiveFPS: Int {
        isBatterySaverActive ? Config.batterySaverFPS : currentFPS
    }

    private var effectiveSpawnMultiplier: Double {
        isBatterySaverActive ? Config.batterySaverSpawnMultiplier : 1.0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityTracker.shared.requestPermissionOnce()
        rebuildOverlays()
        setupStatusItem()
        setupObservers()
    }

    private func setupObservers() {
        WindowTracker.installMouseMonitorsIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 저전력 모드(Low Power Mode) 켜짐/꺼짐 감지
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // 전원 공급원(배터리 ↔ 전원 어댑터) 변경 감지
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                delegate.powerSourceChanged()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // 화면 슬립 / 세션 비활성화 / 앱 전환 / 스페이스 전환 감지
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
        wsCenter.addObserver(
            self,
            selector: #selector(frontmostContextChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(frontmostContextChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // 전체화면으로 일시정지된 화면에서도 전체화면 해제 시 자동 재개할 수 있도록 주기적으로 확인
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: Config.fullscreenPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullscreenStates()
            }
        }
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
        let windowList = WindowTracker.sharedWindowList(forceRefresh: true)

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
            view.preferredFramesPerSecond = effectiveFPS
            view.ignoresSiblingOrder = true
            view.autoresizingMask = [.width, .height]

            let tracker = WindowTracker()
            tracker.screenFrame = frame
            tracker.primaryScreenHeight = primaryHeight
            let isFullscreen = tracker.isFrontmostAppFullscreen(in: windowList)
            let shouldPause = isGloballyPaused || isFullscreen

            let scene = SnowScene(size: frame.size)
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.intensity = currentIntensity
            scene.spawnRateMultiplier = effectiveSpawnMultiplier
            scene.isSnowEnabled = isSnowEnabled
            scene.isSnowmanEnabled = isSnowmanEnabled
            scene.isOrnamentsEnabled = isOrnamentsEnabled
            scene.tracker = tracker
            view.presentScene(scene)
            view.isPaused = shouldPause

            window.contentView = view
            window.setFrame(frame, display: true)
            if !shouldPause {
                window.orderFrontRegardless()
            }

            overlays.append(
                ScreenOverlay(
                    window: window,
                    view: view,
                    scene: scene,
                    tracker: tracker,
                    isFullscreenPaused: isFullscreen
                )
            )
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
        menu.autoenablesItems = false
        menu.delegate = self

        // 1. 눈 오는 기능 섹션
        let snowToggle = NSMenuItem(title: "눈 내리기", action: #selector(toggleSnow), keyEquivalent: "")
        snowToggle.target = self
        snowToggle.state = isSnowEnabled ? .on : .off
        menu.addItem(snowToggle)
        snowItem = snowToggle

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
        intensityRoot.isEnabled = isSnowEnabled
        menu.addItem(intensityRoot)
        intensityRootItem = intensityRoot

        let snowmanToggle = NSMenuItem(title: "눈사람 표시", action: #selector(toggleSnowman), keyEquivalent: "")
        snowmanToggle.target = self
        snowmanToggle.state = isSnowmanEnabled ? .on : .off
        snowmanToggle.isEnabled = isSnowEnabled
        menu.addItem(snowmanToggle)
        snowmanItem = snowmanToggle

        let shake = NSMenuItem(title: "쌓인 눈 털기", action: #selector(shakeOffSnow), keyEquivalent: "")
        shake.target = self
        shake.isEnabled = isSnowEnabled
        menu.addItem(shake)
        shakeItem = shake

        menu.addItem(.separator())

        // 2. 크리스마스 조명 기능 섹션 (눈 기능과 독립적으로 켜고 끌 수 있음)
        let ornamentsToggle = NSMenuItem(title: "크리스마스 조명", action: #selector(toggleOrnaments), keyEquivalent: "")
        ornamentsToggle.target = self
        ornamentsToggle.state = isOrnamentsEnabled ? .on : .off
        menu.addItem(ornamentsToggle)
        ornamentsItem = ornamentsToggle

        menu.addItem(.separator())

        // 3. 공통 렌더링 및 실행 설정
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

        let batteryMenu = NSMenu()
        for mode in BatterySaverMode.allCases {
            let mi = NSMenuItem(title: mode.title, action: #selector(selectBatterySaver(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = (mode == batterySaverMode) ? .on : .off
            batteryMenu.addItem(mi)
            batterySaverItems.append(mi)
        }
        let batteryRoot = NSMenuItem(title: "배터리 절약", action: nil, keyEquivalent: "")
        batteryRoot.submenu = batteryMenu
        menu.addItem(batteryRoot)

        let pause = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

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

    @objc private func toggleSnow() {
        isSnowEnabled.toggle()
        UserDefaults.standard.set(isSnowEnabled, forKey: "snowEnabled")
        snowItem?.state = isSnowEnabled ? .on : .off
        intensityRootItem?.isEnabled = isSnowEnabled
        snowmanItem?.isEnabled = isSnowEnabled
        shakeItem?.isEnabled = isSnowEnabled
        for overlay in overlays {
            overlay.scene.isSnowEnabled = isSnowEnabled
        }
        updatePauseState()
    }

    @objc private func toggleSnowman() {
        isSnowmanEnabled.toggle()
        UserDefaults.standard.set(isSnowmanEnabled, forKey: "snowmanEnabled")
        snowmanItem?.state = isSnowmanEnabled ? .on : .off
        for overlay in overlays {
            overlay.scene.isSnowmanEnabled = isSnowmanEnabled
        }
    }

    @objc private func toggleOrnaments() {
        isOrnamentsEnabled.toggle()
        UserDefaults.standard.set(isOrnamentsEnabled, forKey: "ornamentsEnabled")
        ornamentsItem?.state = isOrnamentsEnabled ? .on : .off
        for overlay in overlays {
            overlay.scene.isOrnamentsEnabled = isOrnamentsEnabled
        }
        updatePauseState()
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
        applyPerformanceSettings()
        for mi in fpsItems {
            mi.state = (mi.representedObject as? Int) == fps ? .on : .off
        }
    }

    @objc private func selectBatterySaver(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = BatterySaverMode(rawValue: raw) else { return }
        batterySaverMode = mode
        UserDefaults.standard.set(raw, forKey: "batterySaverMode")
        isOnBattery = Self.checkOnBatteryPower()
        applyPerformanceSettings()
        for mi in batterySaverItems {
            mi.state = (mi.representedObject as? String) == raw ? .on : .off
        }
    }

    private func powerSourceChanged() {
        let onBattery = Self.checkOnBatteryPower()
        guard onBattery != isOnBattery else { return }
        isOnBattery = onBattery
        applyPerformanceSettings()
    }

    private func applyPerformanceSettings() {
        let fps = effectiveFPS
        let multiplier = effectiveSpawnMultiplier
        for overlay in overlays {
            overlay.view.preferredFramesPerSecond = fps
            overlay.scene.spawnRateMultiplier = multiplier
        }
    }

    /// IOPSCopyPowerSourcesInfo를 사용해 현재 배터리 전원으로 동작 중인지 확인.
    private static func checkOnBatteryPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey as String] as? String else { continue }
            if state == (kIOPSBatteryPowerValue as String) {
                return true
            }
        }
        return false
    }

    @objc private func togglePause() {
        isUserPaused.toggle()
        pauseItem?.title = isUserPaused ? "다시 시작" : "일시정지"
        updatePauseState()
    }

    @objc nonisolated private func powerStateChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.updatePauseState()
        }
    }

    @objc private func frontmostContextChanged() {
        refreshFullscreenStates(forceSnapshot: true)
    }

    @objc private func screensDidSleep() {
        isDisplaySleeping = true
        updatePauseState()
    }

    @objc private func screensDidWake() {
        isDisplaySleeping = false
        refreshFullscreenStates(forceSnapshot: true)
        updatePauseState()
    }

    @objc private func sessionDidResignActive() {
        isSessionInactive = true
        updatePauseState()
    }

    @objc private func sessionDidBecomeActive() {
        isSessionInactive = false
        refreshFullscreenStates(forceSnapshot: true)
        updatePauseState()
    }

    /// 각 디스플레이별로 최전면 앱이 전체화면인지 확인하고 변경 시 일시정지/재개 반영
    private func refreshFullscreenStates(forceSnapshot: Bool = false) {
        guard !isGloballyPaused, !overlays.isEmpty else { return }
        let windowList = WindowTracker.sharedWindowList(forceRefresh: forceSnapshot)
        var changed = false
        for i in overlays.indices {
            let fullscreen = overlays[i].tracker.isFrontmostAppFullscreen(in: windowList)
            if overlays[i].isFullscreenPaused != fullscreen {
                overlays[i].isFullscreenPaused = fullscreen
                changed = true
            }
        }
        if changed {
            updatePauseState()
        }
    }

    private func updatePauseState() {
        let globalPause = isGloballyPaused
        for overlay in overlays {
            let shouldPause = globalPause || overlay.isFullscreenPaused
            guard overlay.view.isPaused != shouldPause else { continue }
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
