import AppKit

struct TrackedWindow {
    let id: CGWindowID
    let frame: CGRect      // scene 좌표 (원점: 화면 왼쪽 아래, y 위로 증가)
}

/// 다른 앱의 창 위치를 읽어옴.
/// CGWindowListCopyWindowInfo는 창의 "위치/크기"만 읽으면 별도 권한이 필요 없음
/// (창 제목이나 내용은 절대 읽지 않음).
final class WindowTracker {
    var screenFrame: CGRect = .zero
    var primaryScreenHeight: CGFloat = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// 해당 디스플레이에 보이는 일반 창 목록. 앞(front)에 있는 창부터 순서대로.
    func currentWindows() -> [TrackedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let screenRect = CGRect(origin: .zero, size: screenFrame.size)
        var result: [TrackedWindow] = []

        for info in list {
            // layer 0 = 일반 앱 창 (메뉴바, Dock, 알림 등은 다른 layer)
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

            // 좌표 변환: CGWindowList는 원점이 메인 디스플레이 왼쪽 "위"이고 y가 아래로 증가.
            // 각 화면의 SpriteKit scene은 원점이 해당 화면의 왼쪽 "아래"이고 y가 위로 증가.
            let frame = CGRect(
                x: cgRect.minX - screenFrame.minX,
                y: primaryScreenHeight - cgRect.maxY - screenFrame.minY,
                width: cgRect.width,
                height: cgRect.height
            )
            guard frame.intersects(screenRect) else { continue }
            result.append(TrackedWindow(id: id, frame: frame))
        }
        return result
    }
}
