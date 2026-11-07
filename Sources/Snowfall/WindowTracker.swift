import AppKit

struct TrackedWindow {
    let id: CGWindowID
    let frame: CGRect      // scene 좌표 (원점: 화면 왼쪽 아래, y 위로 증가)
    var kind: SurfaceKind = .window
}

/// 다른 앱의 창 위치 및 (손쉬운 사용 권한 허용 시) Dock / 바탕화면 아이콘 위치를 읽어옴.
/// CGWindowListCopyWindowInfo는 창의 "위치/크기"만 읽으면 별도 권한이 필요 없음
/// (창 제목이나 내용은 절대 읽지 않음).
@MainActor
final class WindowTracker {
    var screenFrame: CGRect = .zero
    var primaryScreenHeight: CGFloat = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private static var cachedWindowList: [[String: Any]] = []
    private static var lastSnapshotTime: TimeInterval = -999
    private static var lastActivityTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private static var mouseMonitor: Any?

    /// 마우스 클릭/드래그 글로벌 모니터를 등록하여 창 전환·이동·크기 조절 시 즉시 감지 및 20Hz 폴링 전환.
    static func installMouseMonitorsIfNeeded(onMouseClick: (@MainActor () -> Void)? = nil) {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { event in
            let isClick = (event.type == .leftMouseDown || event.type == .leftMouseUp)
            Task { @MainActor in
                Self.noteActivity()
                if isClick {
                    onMouseClick?()
                }
            }
        }
    }

    /// 마우스 이벤트나 창 위치/개수 변화가 감지되었을 때 호출해 activePollHoldDuration(1.5초) 동안 20Hz 폴링 유지.
    static func noteActivity() {
        lastActivityTime = ProcessInfo.processInfo.systemUptime
    }

    /// 평상시에는 Config.idlePollHz(4Hz), 마우스 이벤트 또는 창 변화 후 1.5초 동안은 20Hz 폴링 주기를 반환.
    static var currentPollInterval: TimeInterval {
        let elapsed = ProcessInfo.processInfo.systemUptime - lastActivityTime
        return elapsed < Config.activePollHoldDuration
            ? Config.windowPollInterval
            : Config.idleWindowPollInterval
    }

    /// 멀티 디스플레이 환경에서 폴링 주기당 CGWindowListCopyWindowInfo를 1회만 호출하여
    /// 모든 화면의 WindowTracker가 동일한 창 목록 스냅샷을 공유함.
    static func sharedWindowList(forceRefresh: Bool = false) -> [[String: Any]] {
        let now = ProcessInfo.processInfo.systemUptime
        if forceRefresh || now - lastSnapshotTime >= currentPollInterval * 0.8 {
            lastSnapshotTime = now
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            cachedWindowList = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        }
        return cachedWindowList
    }

    /// 최전면(frontmost) 앱이 이 화면(screenFrame)에서 전체화면(fullscreen) 상태인지 판정.
    func isFrontmostAppFullscreen(in windowList: [[String: Any]]? = nil) -> Bool {
        let list = windowList ?? Self.sharedWindowList()
        guard screenFrame.width > 0, screenFrame.height > 0,
              let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontPID != ownPID else {
            return false
        }

        let presentation = NSApp.currentSystemPresentationOptions
        let systemFullscreen = !presentation.intersection([.fullScreen, .autoHideMenuBar, .hideMenuBar]).isEmpty

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == frontPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01 else { continue }

            let frame = toSceneFrame(cgRect)
            guard abs(frame.minX) <= 2,
                  abs(frame.minY) <= 2,
                  frame.width >= screenFrame.width - 2 else { continue }

            // 화면 전체를 덮는 전체화면 창이거나, 노치(카메라 영역) 아래를 모두 채운 macOS 네이티브 전체화면 스페이스인 경우
            if frame.height >= screenFrame.height - 2 || (systemFullscreen && frame.height >= screenFrame.height - 48) {
                return true
            }
        }
        return false
    }

    /// 해당 디스플레이에 보이는 표면 목록 (Dock 아이콘 → 일반 창 → 바탕화면 아이콘 순서, 앞부터 뒤로).
    func currentWindows(from windowList: [[String: Any]]? = nil) -> [TrackedWindow] {
        let list = windowList ?? Self.sharedWindowList()
        let screenRect = CGRect(origin: .zero, size: screenFrame.size)
        var result: [TrackedWindow] = []

        let axSurfaces = AccessibilityTracker.shared.currentSurfaces()

        // 1. Dock 아이템 (가장 앞에 표시됨)
        for surface in axSurfaces.dockItems {
            let frame = toSceneFrame(surface.cgRect)
            if frame.intersects(screenRect) {
                result.append(TrackedWindow(id: surface.id, frame: frame, kind: surface.kind))
            }
        }

        // 2. 일반 앱 창 (layer 0, 앞에서 뒤 순서) — 공유된 스냅샷 사용
        let excludedOwners: Set<String> = ["WindowManager", "Dock", "Control Center", "Notification Center"]
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            if let owner = info[kCGWindowOwnerName as String] as? String,
               excludedOwners.contains(owner) {
                continue
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01,
                  cgRect.width >= Config.minWindowSize.width,
                  cgRect.height >= Config.minWindowSize.height
            else { continue }

            let frame = toSceneFrame(cgRect)
            // 왼쪽 스테이지 매니저 썸네일 영역에 걸친 작은 프리뷰 창은 제외
            if frame.minX < Config.stageManagerStripWidth && frame.width < 260 {
                continue
            }
            guard frame.intersects(screenRect) else { continue }
            result.append(TrackedWindow(id: id, frame: frame, kind: .window))
        }

        // 3. 바탕화면 아이콘 (가장 뒤에 있으므로 앞의 일반 창들에 의해 가려짐)
        for surface in axSurfaces.desktopIcons {
            let frame = toSceneFrame(surface.cgRect)
            if frame.intersects(screenRect) {
                result.append(TrackedWindow(id: surface.id, frame: frame, kind: surface.kind))
            }
        }

        return result
    }

    /// 좌표 변환: CGWindowList / AXUIElement는 원점이 메인 디스플레이 왼쪽 "위"이고 y가 아래로 증가.
    /// 각 화면의 SpriteKit scene은 원점이 해당 화면의 왼쪽 "아래"이고 y가 위로 증가.
    private func toSceneFrame(_ cgRect: CGRect) -> CGRect {
        CGRect(
            x: cgRect.minX - screenFrame.minX,
            y: primaryScreenHeight - cgRect.maxY - screenFrame.minY,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
