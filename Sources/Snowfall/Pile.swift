import SpriteKit
import AppKit

/// 창 하나의 윗변에 쌓인 눈.
/// heightmap 방식: 창 폭을 columnWidth 간격의 칸(column)으로 나누고 칸마다 높이를 저장.
@MainActor
final class Pile {
    let windowID: CGWindowID
    private(set) var frame: CGRect = .zero
    private(set) var originX: CGFloat = 0
    private(set) var heights: [CGFloat] = []
    private(set) var visible: [Bool] = []     // 앞에 있는 창에 가려진 칸은 false
    var spillLeft: CGFloat = 0                // 왼쪽 끝으로 흘러넘친 양
    var spillRight: CGFloat = 0
    private(set) var isDirty = true           // true면 다음 frame에 다시 그림
    private var needsRelax = false
    let node = SKShapeNode()

    init(windowID: CGWindowID, frame: CGRect) {
        self.windowID = windowID
        node.fillColor = NSColor(white: 1.0, alpha: 0.97)
        // 흰 창(light mode) 위에서도 보이도록 옅은 회청색 테두리
        node.strokeColor = NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.86, alpha: 0.9)
        node.lineWidth = 0.8
        node.isAntialiased = true
        node.zPosition = 5
        reset(frame: frame)
    }

    // MARK: - Geometry

    /// 눈이 놓이는 기준선 (창 윗변보다 살짝 아래 → 얹혀 있는 느낌)
    var base: CGFloat { frame.maxY - 0.5 }
    var endX: CGFloat { originX + CGFloat(heights.count) * Config.columnWidth }
    var totalSnow: CGFloat { heights.reduce(0, +) }

    func columnCenterX(_ c: Int) -> CGFloat {
        originX + (CGFloat(c) + 0.5) * Config.columnWidth
    }

    func column(atX x: CGFloat) -> Int? {
        guard !heights.isEmpty else { return nil }
        let idx = Int(((x - originX) / Config.columnWidth).rounded(.down))
        return (0..<heights.count).contains(idx) ? idx : nil
    }

    func hasMoved(to newFrame: CGRect) -> Bool {
        let t = Config.moveThreshold
        return abs(newFrame.minX - frame.minX) > t
            || abs(newFrame.maxY - frame.maxY) > t
            || abs(newFrame.width - frame.width) > t
    }

    /// 윗변은 그대로이고 아래쪽만 바뀐 경우 (예: 창 높이를 아래로 늘림) → 눈 유지
    func updateFrame(_ newFrame: CGRect) {
        frame = newFrame
    }

    // MARK: - State

    func reset(frame newFrame: CGRect) {
        frame = newFrame
        let usable = max(0, newFrame.width - Config.pileEdgeInset * 2)
        let count = Int(usable / Config.columnWidth)
        originX = newFrame.midX - CGFloat(count) * Config.columnWidth / 2
        heights = Array(repeating: 0, count: count)
        visible = Array(repeating: true, count: count)
        spillLeft = 0
        spillRight = 0
        needsRelax = false
        isDirty = true
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        spillLeft = 0
        spillRight = 0
        needsRelax = false
        isDirty = true
    }

    /// 눈송이 하나가 c번째 칸에 착지. 주변 칸에도 조금씩 나눠 쌓음.
    func add(at c: Int, amount: CGFloat) {
        let cap = Config.maxPileHeight
        heights[c] = min(cap, heights[c] + amount * 0.5)
        if c > 0 { heights[c - 1] = min(cap, heights[c - 1] + amount * 0.25) }
        if c + 1 < heights.count { heights[c + 1] = min(cap, heights[c + 1] + amount * 0.25) }
        needsRelax = true
        isDirty = true
    }

    /// 경사가 너무 가파른 곳의 눈을 낮은 쪽으로 흘려보냄 (angle of repose).
    /// 양 끝 밖은 높이 0으로 취급 → 끝으로 흘러간 눈은 spill로 모였다가 떨어짐.
    func relax() {
        guard needsRelax, !heights.isEmpty else { return }
        let n = heights.count
        let limit = Config.maxSlope
        var anyChange = false

        for _ in 0..<Config.relaxPassesPerFrame {
            var changed = false
            for i in -1..<n {
                let a = i >= 0 ? heights[i] : 0
                let b = i + 1 < n ? heights[i + 1] : 0
                let diff = a - b
                guard abs(diff) > limit else { continue }
                let t = (abs(diff) - limit) * 0.5
                if diff > 0 {
                    // 왼쪽(i)이 더 높음 → 오른쪽으로 이동. (a > 0 이므로 i >= 0 보장)
                    heights[i] -= t
                    if i + 1 < n { heights[i + 1] += t } else { spillRight += t }
                } else {
                    // 오른쪽(i+1)이 더 높음 → 왼쪽으로 이동. (b > 0 이므로 i+1 < n 보장)
                    heights[i + 1] -= t
                    if i >= 0 { heights[i] += t } else { spillLeft += t }
                }
                changed = true
            }
            if !changed { break }
            anyChange = true
        }

        if anyChange { isDirty = true } else { needsRelax = false }
    }

    /// 앞에 있는 창들(occluders)이 이 창의 윗변을 덮고 있는 칸은 숨김.
    func updateVisibility(occluders: [CGRect]) {
        guard !heights.isEmpty else { return }
        let probeY = base + 2
        let relevant = occluders.filter {
            $0.minY <= probeY && $0.maxY > probeY && $0.maxX > originX && $0.minX < endX
        }
        var changed = false
        for c in visible.indices {
            let x = columnCenterX(c)
            let v = !relevant.contains { x >= $0.minX && x < $0.maxX }
            if v != visible[c] {
                visible[c] = v
                changed = true
            }
        }
        if changed { isDirty = true }
    }

    // MARK: - Drawing

    /// 보이는 칸들을 이어 부드러운 곡선 모양(path)으로 그림.
    func redraw() {
        isDirty = false
        let path = CGMutablePath()
        let cw = Config.columnWidth
        let n = heights.count
        var c = 0

        while c < n {
            guard visible[c], heights[c] > 0.05 else { c += 1; continue }
            let start = c
            while c < n, visible[c], heights[c] > 0.05 { c += 1 }
            let end = c - 1

            var pts: [CGPoint] = [CGPoint(x: originX + CGFloat(start) * cw, y: base)]
            for i in start...end {
                pts.append(CGPoint(x: columnCenterX(i), y: base + heights[i]))
            }
            pts.append(CGPoint(x: originX + CGFloat(end + 1) * cw, y: base))

            // 점들 사이 중간점을 quad curve로 이어 각진 느낌 제거
            path.move(to: pts[0])
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2,
                                  y: (pts[i - 1].y + pts[i].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i - 1])
            }
            path.addLine(to: pts[pts.count - 1])
            path.closeSubpath()
        }
        node.path = path
    }
}
