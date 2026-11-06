import SpriteKit
import AppKit

/// 창 아랫변에 매달려 자라는 고드름 하나.
struct Icicle {
    let x: CGFloat
    let baseWidth: CGFloat
    let maxLength: CGFloat
    let growthSpeed: CGFloat
    let spawnOffset: TimeInterval
    var length: CGFloat = 0
    var isVisible: Bool = true
}

/// 창 하나의 윗변에 쌓인 눈과 아랫변에 자라는 고드름.
/// heightmap 방식: 창 폭을 columnWidth 간격의 칸(column)으로 나누고 칸마다 높이를 저장.
@MainActor
final class Pile {
    let windowID: CGWindowID
    let kind: SurfaceKind
    private(set) var frame: CGRect = .zero
    private(set) var originX: CGFloat = 0
    private(set) var heights: [CGFloat] = []
    private(set) var visible: [Bool] = []     // 앞에 있는 창에 가려진 칸은 false
    var spillLeft: CGFloat = 0                // 왼쪽 끝으로 흘러넘친 양
    var spillRight: CGFloat = 0
    private(set) var isDirty = true           // true면 다음 frame에 다시 그림
    private var needsRelax = false

    // 고드름 상태
    private(set) var icicles: [Icicle] = []
    private(set) var stillTime: TimeInterval = 0
    private(set) var iciclesDirty = true

    let node = SKShapeNode()
    let icicleNode = SKShapeNode()

    init(windowID: CGWindowID, frame: CGRect, kind: SurfaceKind = .window) {
        self.windowID = windowID
        self.kind = kind
        node.fillColor = NSColor(white: 1.0, alpha: 0.97)
        // 흰 창(light mode) 위에서도 보이도록 옅은 회청색 테두리
        node.strokeColor = NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.86, alpha: 0.9)
        node.lineWidth = 0.8
        node.isAntialiased = true
        node.zPosition = 5

        // 고드름은 살짝 반투명한 얼음빛(하늘빛 흰색)으로 표현
        icicleNode.fillColor = NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.0, alpha: 0.90)
        icicleNode.strokeColor = NSColor(calibratedRed: 0.62, green: 0.75, blue: 0.90, alpha: 0.92)
        icicleNode.lineWidth = 0.8
        icicleNode.isAntialiased = true
        node.addChild(icicleNode)

        reset(frame: frame)
    }

    // MARK: - Geometry

    /// 눈이 놓이는 기준선 (창 윗변보다 살짝 아래 → 얹혀 있는 느낌)
    var base: CGFloat { frame.maxY - 0.5 }
    /// 고드름이 매달리는 기준선 (창 아랫변보다 살짝 위 → 창 밑에 붙어 있는 느낌)
    var bottomBase: CGFloat { frame.minY + 0.5 }
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

    func hasBottomMoved(to newFrame: CGRect) -> Bool {
        abs(newFrame.minY - frame.minY) > Config.moveThreshold
    }

    /// 윗변은 그대로이고 아래쪽만 바뀐 경우 (예: 창 높이를 아래로 늘림) → 윗변 눈은 유지
    func updateFrame(_ newFrame: CGRect, resetIcicles: Bool) {
        frame = newFrame
        if resetIcicles {
            seedIcicles()
        }
    }

    // MARK: - State

    func reset(frame newFrame: CGRect) {
        frame = newFrame
        let inset = (kind == .window) ? Config.pileEdgeInset : Config.iconEdgeInset
        let usable = max(0, newFrame.width - inset * 2)
        let count = Int(usable / Config.columnWidth)
        originX = newFrame.midX - CGFloat(count) * Config.columnWidth / 2
        heights = Array(repeating: 0, count: count)
        visible = Array(repeating: true, count: count)
        spillLeft = 0
        spillRight = 0
        needsRelax = false
        isDirty = true
        seedIcicles()
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        spillLeft = 0
        spillRight = 0
        needsRelax = false
        isDirty = true
    }

    /// 창 폭에 비례하는 개수로 고드름 위치를 무작위 배치하고 타이머를 0으로 초기화 (일반 창에만 생성)
    func seedIcicles() {
        stillTime = 0
        icicles.removeAll()
        iciclesDirty = true
        guard kind == .window else { return }

        let minX = frame.minX + Config.icicleEdgeInset
        let maxX = frame.maxX - Config.icicleEdgeInset
        let usableWidth = maxX - minX
        guard usableWidth > Config.icicleMinSpacing else { return }

        let targetCount = max(1, Int((Double(usableWidth) / 100.0) * Config.iciclesPer100pt))
        var chosenX: [CGFloat] = []
        var attempts = 0
        while chosenX.count < targetCount && attempts < targetCount * 6 {
            attempts += 1
            let candidate = CGFloat.random(in: minX...maxX)
            if chosenX.allSatisfy({ abs($0 - candidate) >= Config.icicleMinSpacing }) {
                chosenX.append(candidate)
            }
        }
        chosenX.sort()

        for x in chosenX {
            icicles.append(
                Icicle(
                    x: x,
                    baseWidth: CGFloat.random(in: Config.icicleBaseWidthRange),
                    maxLength: CGFloat.random(in: Config.icicleMaxLengthRange),
                    growthSpeed: CGFloat.random(in: Config.icicleGrowthSpeedRange),
                    spawnOffset: TimeInterval.random(in: Config.icicleStaggerRange)
                )
            )
        }
    }

    /// 창이 가만히 있었던 시간을 누적하고, icicleStartDelay가 지나면 고드름을 조금씩 자라게 함
    func stepIcicles(dt: TimeInterval) {
        guard !icicles.isEmpty else { return }
        stillTime += dt
        guard stillTime >= Config.icicleStartDelay else { return }

        let elapsedAfterDelay = stillTime - Config.icicleStartDelay
        var grew = false
        for i in icicles.indices {
            guard icicles[i].isVisible,
                  elapsedAfterDelay >= icicles[i].spawnOffset,
                  icicles[i].length < icicles[i].maxLength else { continue }
            icicles[i].length = min(
                icicles[i].maxLength,
                icicles[i].length + icicles[i].growthSpeed * CGFloat(dt)
            )
            grew = true
        }
        if grew { iciclesDirty = true }
    }

    /// 눈송이 하나가 c번째 칸에 착지. 주변 칸에도 조금씩 나눠 쌓음.
    func add(at c: Int, amount: CGFloat) {
        let cap = (kind == .window) ? Config.maxPileHeight : Config.maxIconPileHeight
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

    /// 앞에 있는 창들(occluders)이 이 창의 윗변/아랫변을 덮고 있는 영역은 숨김.
    func updateVisibility(occluders: [CGRect]) {
        if !heights.isEmpty {
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

        if !icicles.isEmpty {
            let probeBottomY = frame.minY - 2
            let bottomRelevant = occluders.filter {
                $0.minY <= probeBottomY && $0.maxY >= frame.minY && $0.maxX > frame.minX && $0.minX < frame.maxX
            }
            var icicleChanged = false
            for i in icicles.indices {
                let x = icicles[i].x
                let v = !bottomRelevant.contains { x >= $0.minX && x < $0.maxX }
                if v != icicles[i].isVisible {
                    icicles[i].isVisible = v
                    icicleChanged = true
                }
            }
            if icicleChanged { iciclesDirty = true }
        }
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

    /// 아랫변이 가려지지 않은 위치의 고드름들을 뾰족한 얼음 기둥 모양으로 그림.
    func redrawIcicles() {
        iciclesDirty = false
        let path = CGMutablePath()
        let topY = bottomBase

        for icicle in icicles {
            guard icicle.isVisible, icicle.length > 0.5 else { continue }
            let halfW = icicle.baseWidth * 0.5
            let tipY = topY - icicle.length

            path.move(to: CGPoint(x: icicle.x - halfW, y: topY))
            path.addQuadCurve(
                to: CGPoint(x: icicle.x, y: tipY),
                control: CGPoint(x: icicle.x - halfW * 0.35, y: topY - icicle.length * 0.45)
            )
            path.addQuadCurve(
                to: CGPoint(x: icicle.x + halfW, y: topY),
                control: CGPoint(x: icicle.x + halfW * 0.35, y: topY - icicle.length * 0.45)
            )
            path.closeSubpath()
        }
        icicleNode.path = path
    }
}
