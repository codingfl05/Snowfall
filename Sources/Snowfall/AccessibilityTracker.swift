import AppKit
import ApplicationServices

/// 눈이 쌓일 수 있는 표면의 종류.
enum SurfaceKind {
    case window
    case dockItem
    case desktopIcon
}

/// Accessibility API(손쉬운 사용, AXUIElement)를 사용해 Dock 아이콘과 바탕화면 아이콘의 영역을 읽어옴.
/// 권한이 거부되더라도 크래시나 반복 팝업 없이 빈 목록을 반환해 일반 창 전용 모드로 동작함.
@MainActor
final class AccessibilityTracker {
    static let shared = AccessibilityTracker()

    struct RawSurface {
        let id: CGWindowID
        let cgRect: CGRect
        let kind: SurfaceKind
    }

    private var didPrompt = false
    private var lastDockPollTime: TimeInterval = 0
    private var lastDesktopPollTime: TimeInterval = 0
    private var cachedDockItems: [RawSurface] = []
    private var cachedDesktopIcons: [RawSurface] = []

    /// 앱 실행 시 최초 1회만 손쉬운 사용 권한 요청 팝업을 띄움.
    /// 이미 허용/거부된 상태라면 시스템이 중복 팝업을 띄우지 않거나 설정 안내만 수행함.
    func requestPermissionOnce() {
        guard !didPrompt else { return }
        didPrompt = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 현재 Dock 아이템(4Hz 캐싱)들과 바탕화면 아이콘(1Hz 캐싱)들의 글로벌 CG 좌표를 반환.
    func currentSurfaces() -> (dockItems: [RawSurface], desktopIcons: [RawSurface]) {
        // AXIsProcessTrusted()는 팝업 없이 현재 권한 허용 여부만 즉시 확인함
        guard AXIsProcessTrusted() else {
            cachedDockItems.removeAll()
            cachedDesktopIcons.removeAll()
            return ([], [])
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastDockPollTime >= Config.axPollInterval {
            lastDockPollTime = now
            cachedDockItems = fetchDockItems()
        }
        if now - lastDesktopPollTime >= Config.axDesktopPollInterval {
            lastDesktopPollTime = now
            cachedDesktopIcons = fetchDesktopIcons()
        }
        return (cachedDockItems, cachedDesktopIcons)
    }

    // MARK: - Dock items

    private func fetchDockItems() -> [RawSurface] {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }
        let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        // Dock 프로세스가 응답이 느릴 때 메인 스레드가 블로킹되지 않도록 타임아웃(0.1초) 설정
        AXUIElementSetMessagingTimeout(appElement, Config.axMessagingTimeout)
        var results: [RawSurface] = []

        for child in children(of: appElement) {
            guard stringAttribute(kAXRoleAttribute as String, of: child) == "AXList" else { continue }
            for item in children(of: child) {
                let subrole = stringAttribute(kAXSubroleAttribute as String, of: item) ?? ""
                if subrole == "AXSeparatorDockItem" { continue }

                // Dock 아이템 순서(index)가 바뀌어도 눈이 털리지 않도록 제목(title)만으로 ID 생성
                guard let title = stringAttribute(kAXTitleAttribute as String, of: item),
                      !title.isEmpty,
                      let rect = frame(of: item),
                      isValidIconSize(rect.size) else { continue }
                let id = titleHashID(prefix: 0x8000_0000, title: title)
                results.append(RawSurface(id: id, cgRect: rect, kind: .dockItem))
            }
        }
        return results
    }

    // MARK: - Finder desktop icons

    private func fetchDesktopIcons() -> [RawSurface] {
        guard let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return []
        }
        let appElement = AXUIElementCreateApplication(finderApp.processIdentifier)
        // Finder 응답 지연 시 메인 스레드 블로킹 방지를 위해 타임아웃(0.1초) 설정
        AXUIElementSetMessagingTimeout(appElement, Config.axMessagingTimeout)
        var results: [RawSurface] = []
        collectDesktopIcons(from: appElement, depth: 0, insideDesktopContainer: false, into: &results)
        return results
    }

    private func collectDesktopIcons(
        from element: AXUIElement,
        depth: Int,
        insideDesktopContainer: Bool,
        into results: inout [RawSurface]
    ) {
        guard depth <= 5 else { return }
        let role = stringAttribute(kAXRoleAttribute as String, of: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as String, of: element) ?? ""

        // 메뉴바나 일반 파인더 폴더 창(AXStandardWindow, 대화상자 등)은 바탕화면이 아니므로 제외
        if role == "AXMenuBar" { return }
        if role == "AXWindow" && (subrole == "AXStandardWindow" || subrole == "AXDialog" || subrole == "AXSystemDialog") {
            return
        }

        let isDesktopScrollOrGroup = insideDesktopContainer || role == "AXScrollArea" || subrole == "AXDesktopWindow"

        if role == "AXIcon" || (insideDesktopContainer && (role == "AXImage" || role == "AXCell")) {
            if let rect = frame(of: element), isValidIconSize(rect.size) {
                let id = stableID(prefix: 0x9000_0000, element: element, fallbackIndex: results.count)
                results.append(RawSurface(id: id, cgRect: rect, kind: .desktopIcon))
            }
            return
        }

        let kids = children(of: element)
        // 바탕화면 AXGroup 내부의 직접 자식 요소가 아이콘 크기를 가지면 아이콘으로 인식
        if insideDesktopContainer && role == "AXGroup" && kids.isEmpty {
            if let rect = frame(of: element), isValidIconSize(rect.size) {
                let id = stableID(prefix: 0x9000_0000, element: element, fallbackIndex: results.count)
                results.append(RawSurface(id: id, cgRect: rect, kind: .desktopIcon))
            }
            return
        }

        for child in kids {
            collectDesktopIcons(
                from: child,
                depth: depth + 1,
                insideDesktopContainer: isDesktopScrollOrGroup,
                into: &results
            )
        }
    }

    // MARK: - AX Helpers

    private func isValidIconSize(_ size: CGSize) -> Bool {
        size.width >= Config.minIconSize.width
            && size.height >= Config.minIconSize.height
            && size.width <= Config.maxIconSize.width
            && size.height <= Config.maxIconSize.height
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard err == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard err == .success else { return nil }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }

    /// 제목(title) 문자열만으로 고정된 CGWindowID를 생성 (Dock 아이템 등 순서가 바뀌어도 동일한 ID 유지)
    private func titleHashID(prefix: UInt32, title: String) -> CGWindowID {
        var hash: UInt32 = 2166136261
        for byte in title.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return prefix | (hash & 0x0FFF_FFFF)
    }

    /// 바탕화면 아이콘 제목(없을 경우 순번)으로 고정된 CGWindowID를 생성
    private func stableID(prefix: UInt32, element: AXUIElement, fallbackIndex: Int) -> CGWindowID {
        if let title = stringAttribute(kAXTitleAttribute as String, of: element), !title.isEmpty {
            return titleHashID(prefix: prefix, title: title)
        }
        return prefix | UInt32(fallbackIndex & 0x0FFF_FFFF)
    }
}
