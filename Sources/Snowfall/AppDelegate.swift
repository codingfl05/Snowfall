import AppKit
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow?
    private var skView: SKView?
    private var scene: SnowScene?
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var intensityItems: [NSMenuItem] = []
    private let tracker = WindowTracker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlay()
        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Overlay window

    /// 화면 전체를 덮는 투명 창. 클릭은 아래 앱으로 그대로 통과함.
    private func setupOverlay() {
        // MVP는 메인 디스플레이(메뉴바가 있는 화면)만 지원
        guard let screen = NSScreen.screens.first else { return }
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
        view.preferredFramesPerSecond = Config.framesPerSecond
        view.ignoresSiblingOrder = true
        view.autoresizingMask = [.width, .height]

        tracker.screenSize = frame.size
        let scene = SnowScene(size: frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.tracker = tracker
        view.presentScene(scene)

        window.contentView = view
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        overlayWindow = window
        skView = view
        self.scene = scene
    }

    @objc private func screenParametersChanged() {
        guard let screen = NSScreen.screens.first, let window = overlayWindow else { return }
        window.setFrame(screen.frame, display: true)
        tracker.screenSize = screen.frame.size
        scene?.resetForScreenChange()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "❄︎"

        let menu = NSMenu()

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

        let pause = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let shake = NSMenuItem(title: "쌓인 눈 털기", action: #selector(shakeOffSnow), keyEquivalent: "")
        shake.target = self
        menu.addItem(shake)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func selectIntensity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = SnowIntensity(rawValue: raw) else { return }
        scene?.intensity = level
        for mi in intensityItems {
            mi.state = (mi.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func togglePause() {
        guard let view = skView, let window = overlayWindow else { return }
        view.isPaused.toggle()
        if view.isPaused {
            window.orderOut(nil)
            pauseItem?.title = "다시 시작"
        } else {
            window.orderFrontRegardless()
            pauseItem?.title = "일시정지"
        }
    }

    @objc private func shakeOffSnow() {
        scene?.shakeOffAllSnow()
    }
}
