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

    /// 해당 디스플레이에 보이는 표면 목록 (Dock 아이콘 → 일반 창 → 바탕화면 아이콘 순서, 앞부터 뒤로).
    func currentWindows() -> [TrackedWindow] {
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

        // 2. 일반 앱 창 (layer 0, 앞에서 뒤 순서)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                      let id = info[kCGWindowNumber as String] as? CGWindowID,
                      let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
                else { continue }

                let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
                guard alpha > 0.01,
                      cgRect.width >= Config.minWindowSize.width,
                      cgRect.height >= Config.minWindowSize.height
                else { continue }

                let frame = toSceneFrame(cgRect)
                guard frame.intersects(screenRect) else { continue }
                result.append(TrackedWindow(id: id, frame: frame, kind: .window))
            }
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
