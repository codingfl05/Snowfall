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

/// 창 상단 테두리 가랜드에 매달린 크리스마스 오나먼트 및 전구 하나.
@MainActor
final class OrnamentBulb {
    let x: CGFloat
    let y: CGFloat
    let anchorY: CGFloat
    let isBauble: Bool          // true면 줄에 매달린 둥근 방울 오나먼트, false면 전선에 붙은 꼬마전구
    let color: NSColor
    var phase: Double
    var isVisible: Bool = true

    let containerNode = SKNode()
    let baubleSprite: SKSpriteNode?
    let glowSprite: SKSpriteNode
    let coreSprite: SKSpriteNode

    init(
        x: CGFloat,
        y: CGFloat,
        anchorY: CGFloat,
        isBauble: Bool,
        color: NSColor,
        phase: Double,
        baubleTexture: SKTexture,
        glowTexture: SKTexture,
        coreTexture: SKTexture
    ) {
        self.x = x
        self.y = y
        self.anchorY = anchorY
        self.isBauble = isBauble
        self.color = color
        self.phase = phase

        containerNode.position = CGPoint(x: x, y: y)

        if isBauble {
            let d = Config.ornamentBaubleRadius * 2
            let body = SKSpriteNode(texture: baubleTexture, size: CGSize(width: d, height: d))
            body.color = color
            body.colorBlendFactor = 0.82
            body.zPosition = 1
            containerNode.addChild(body)
            self.baubleSprite = body
        } else {
            self.baubleSprite = nil
        }

        // 전구 빛 번짐(halo): additive 블렌딩으로 은은하게 퍼지는 빛 표현
        let glowDiameter = (isBauble ? Config.ornamentBaubleRadius : Config.ornamentBulbRadius) * 4.2
        let glow = SKSpriteNode(texture: glowTexture, size: CGSize(width: glowDiameter, height: glowDiameter))
        glow.color = color
        glow.colorBlendFactor = 1.0
        glow.blendMode = .add
        glow.zPosition = 2
        containerNode.addChild(glow)
        self.glowSprite = glow

        // 전구 중심의 밝은 필라멘트 코어
        let coreDiameter = (isBauble ? Config.ornamentBulbRadius * 1.6 : Config.ornamentBulbRadius * 2.0)
        let core = SKSpriteNode(texture: coreTexture, size: CGSize(width: coreDiameter, height: coreDiameter))
        core.color = color
        core.colorBlendFactor = 0.35
        core.blendMode = .add
        core.zPosition = 3
        containerNode.addChild(core)
        self.coreSprite = core
    }
}

/// 창 하나의 윗변에 쌓인 눈, 상단 테두리의 크리스마스 가랜드/오나먼트, 아랫변에 자라는 고드름.
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

    // 크리스마스 오나먼트 상태
    var ornamentsEnabled: Bool = Config.defaultOrnamentsEnabled {
        didSet {
            guard ornamentsEnabled != oldValue else { return }
            if ornamentsEnabled {
                seedOrnaments()
                redrawOrnaments()
            } else {
                clearOrnaments()
            }
        }
    }
    private(set) var ornaments: [OrnamentBulb] = []
    private(set) var ornamentsDirty = true

    let node = SKShapeNode()
    let shadowNode = SKShapeNode()
    let icicleNode = SKShapeNode()
    let garlandCordNode = SKShapeNode()
    let ornamentCapNode = SKShapeNode()
    let ornamentLayerNode = SKNode()

    // 모든 창이 공유하는 오나먼트/전구 텍스처 (메모리 절약)
    private static let sharedBaubleTexture = Pile.makeBaubleTexture()
    private static let sharedGlowTexture = Pile.makeGlowTexture()
    private static let sharedCoreTexture = Pile.makeCoreTexture()
    private static let ornamentPalette: [NSColor] = [
        NSColor(calibratedRed: 0.98, green: 0.22, blue: 0.26, alpha: 1.0), // 루비 레드
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.22, alpha: 1.0), // 웜 골드
        NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.46, alpha: 1.0), // 에메랄드 그린
        NSColor(calibratedRed: 0.36, green: 0.76, blue: 1.00, alpha: 1.0), // 아이스 블루
        NSColor(calibratedRed: 1.00, green: 0.52, blue: 0.72, alpha: 1.0)  // 로즈 핑크
    ]

    init(
        windowID: CGWindowID,
        frame: CGRect,
        kind: SurfaceKind = .window,
        ornamentsEnabled: Bool = Config.defaultOrnamentsEnabled
    ) {
        self.windowID = windowID
        self.kind = kind
        self.ornamentsEnabled = ornamentsEnabled
        node.fillColor = NSColor(white: 1.0, alpha: 0.97)
        // 흰 창(light mode)이나 노란 폴더 위에서도 입체적으로 보이도록 은은한 빙하빛 테두리
        node.strokeColor = NSColor(calibratedRed: 0.66, green: 0.75, blue: 0.88, alpha: 0.92)
        node.lineWidth = 0.9
        node.lineJoin = .round
        node.isAntialiased = true
        node.zPosition = 5

        // 눈더미 아랫부분의 부드러운 그림자
        shadowNode.fillColor = .clear
        shadowNode.strokeColor = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.62, alpha: 0.28)
        shadowNode.lineWidth = 1.6
        shadowNode.lineCap = .round
        shadowNode.zPosition = -1
        node.addChild(shadowNode)

        // 고드름은 살짝 반투명한 얼음빛(하늘빛 흰색)으로 표현
        icicleNode.fillColor = NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.0, alpha: 0.90)
        icicleNode.strokeColor = NSColor(calibratedRed: 0.62, green: 0.75, blue: 0.90, alpha: 0.92)
        icicleNode.lineWidth = 0.8
        icicleNode.isAntialiased = true
        node.addChild(icicleNode)

        // 크리스마스 가랜드 전선 (짙은 전나무 그린)
        garlandCordNode.fillColor = .clear
        garlandCordNode.strokeColor = NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.23, alpha: 0.88)
        garlandCordNode.lineWidth = 1.3
        garlandCordNode.lineCap = .round
        garlandCordNode.lineJoin = .round
        garlandCordNode.zPosition = -2
        node.addChild(garlandCordNode)

        // 오나먼트 금색 매듭 줄과 꼭지 캡
        ornamentCapNode.fillColor = NSColor(calibratedRed: 0.92, green: 0.76, blue: 0.36, alpha: 0.95)
        ornamentCapNode.strokeColor = NSColor(calibratedRed: 0.82, green: 0.66, blue: 0.28, alpha: 0.85)
        ornamentCapNode.lineWidth = 0.85
        ornamentCapNode.zPosition = -1.5
        node.addChild(ornamentCapNode)

        ornamentLayerNode.zPosition = -1.2
        node.addChild(ornamentLayerNode)

        reset(frame: frame)
    }

    // MARK: - Geometry

    /// 눈이 놓이는 기준선 (바탕화면 폴더 아이콘은 상단 빈 셀 여백만큼 내려서 실제 폴더 윗변에 밀착)
    var base: CGFloat {
        switch kind {
        case .window:
            return frame.maxY - 0.5
        case .dockItem:
            return frame.maxY - 2.0
        case .desktopIcon:
            return frame.maxY - Config.desktopIconTopOffset
        }
    }
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
        let inset: CGFloat
        switch kind {
        case .window: inset = Config.pileEdgeInset
        case .dockItem: inset = Config.iconEdgeInset
        case .desktopIcon: inset = Config.desktopIconEdgeInset
        }
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
        seedOrnaments()
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        spillLeft = 0
        spillRight = 0
        needsRelax = false
        isDirty = true
    }

    /// 고드름 상태와 경로를 모두 지움
    func clearIcicles() {
        stillTime = 0
        icicles.removeAll()
        icicleNode.path = nil
        iciclesDirty = false
    }

    /// 크리스마스 오나먼트와 가랜드 노드를 모두 제거하여 메모리 해제
    func clearOrnaments() {
        for ornament in ornaments {
            ornament.containerNode.removeFromParent()
        }
        ornaments.removeAll()
        garlandCordNode.path = nil
        ornamentCapNode.path = nil
        ornamentsDirty = false
    }

    /// 창 상단 테두리(신호등 버튼 오른쪽 ~ 우측 상단 모서리)를 따라 가랜드 전선과 오나먼트/전구를 배치
    func seedOrnaments() {
        clearOrnaments()
        guard kind == .window,
              ornamentsEnabled,
              frame.width >= Config.ornamentMinWindowWidth else { return }

        let startX = frame.minX + Config.ornamentEdgeInsetLeft
        let endX = frame.maxX - Config.ornamentEdgeInsetRight
        let span = endX - startX
        guard span >= Config.ornamentSpacing else { return }

        let segmentCount = max(2, Int((span / Config.ornamentSpacing).rounded()))
        let stepX = span / CGFloat(segmentCount)
        let cordTopY = frame.maxY - 1.5
        let palette = Self.ornamentPalette
        // 창 ID마다 색상 시작 인덱스를 다르게 해 창마다 다채로운 조합을 만듦
        let colorSeed = Int(windowID) % palette.count

        var idx = 0
        for i in 0...segmentCount {
            let anchorX = startX + CGFloat(i) * stepX
            let isBauble = (i % 2 == 0) || (i == segmentCount)
            let drop = isBauble ? Config.ornamentBaubleDrop : 2.2
            let color = palette[(colorSeed + idx) % palette.count]
            let phase = Double(idx) * 0.85 + Double(windowID % 7) * 0.4

            let item = OrnamentBulb(
                x: anchorX,
                y: cordTopY - drop,
                anchorY: cordTopY,
                isBauble: isBauble,
                color: color,
                phase: phase,
                baubleTexture: Self.sharedBaubleTexture,
                glowTexture: Self.sharedGlowTexture,
                coreTexture: Self.sharedCoreTexture
            )
            ornamentLayerNode.addChild(item.containerNode)
            ornaments.append(item)
            idx += 1

            // 각 가랜드 처짐(swag) 곡선의 가운데 아랫부분에도 꼬마전구 배치
            if i < segmentCount {
                let midX = anchorX + stepX * 0.5
                let swagY = cordTopY - Config.ornamentSwagDrop
                let bulbColor = palette[(colorSeed + idx) % palette.count]
                let bulbPhase = Double(idx) * 0.85 + Double(windowID % 7) * 0.4

                let midBulb = OrnamentBulb(
                    x: midX,
                    y: swagY - 1.8,
                    anchorY: swagY,
                    isBauble: false,
                    color: bulbColor,
                    phase: bulbPhase,
                    baubleTexture: Self.sharedBaubleTexture,
                    glowTexture: Self.sharedGlowTexture,
                    coreTexture: Self.sharedCoreTexture
                )
                ornamentLayerNode.addChild(midBulb.containerNode)
                ornaments.append(midBulb)
                idx += 1
            }
        }
        ornamentsDirty = true
    }

    /// CPU 부하에 비례하는 phaseDelta만큼 오나먼트 전구 위상을 진행시키고 빛 번짐(glow)과 밝기를 갱신
    func stepOrnaments(phaseDelta: Double, overload: Double) {
        guard !ornaments.isEmpty else { return }
        let minScale = Config.ornamentGlowScaleRange.lowerBound
        let maxScale = Config.ornamentGlowScaleRange.upperBound

        for (i, item) in ornaments.enumerated() {
            item.phase += phaseDelta
            guard item.isVisible else { continue }

            // 기본 사인파 숨쉬기 + CPU 과부하 시 고주파 반짝임(sparkle) 파형 합성
            let primary = 0.5 + 0.5 * sin(item.phase)
            let brightness: Double
            if overload > 0 {
                let sparkle = 0.5 + 0.5 * sin(item.phase * 2.8 + Double(i) * 1.3)
                brightness = primary * (1.0 - 0.42 * overload) + sparkle * (0.42 * overload)
            } else {
                brightness = primary
            }

            let b = CGFloat(max(0.0, min(1.0, brightness)))
            let overloadBoost = CGFloat(1.0 + 0.22 * overload)
            let scale = (minScale + (maxScale - minScale) * b) * overloadBoost

            item.glowSprite.alpha = 0.16 + (0.68 + CGFloat(0.15 * overload)) * b
            item.glowSprite.setScale(scale)
            item.coreSprite.alpha = 0.30 + 0.70 * pow(b, 1.35)
        }
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

    /// 양 끝으로 갈수록 최대 높이가 둥글게 낮아지는 아치형(dome) 한계값 계산 (네모난 벽돌 모양 방지)
    private func columnCap(at c: Int) -> CGFloat {
        let baseCap = (kind == .window) ? Config.maxPileHeight : Config.maxIconPileHeight
        let n = heights.count
        guard n > 2 else { return baseCap * 0.6 }
        let distFromEdge = min(c, n - 1 - c)
        let taperCols = max(2, min(Config.pileTaperColumns, n / 2))
        if distFromEdge < taperCols {
            let ratio = CGFloat(distFromEdge + 1) / CGFloat(taperCols + 1)
            let arch = sin(ratio * .pi * 0.5)
            return baseCap * (0.22 + 0.78 * arch)
        }
        return baseCap
    }

    /// 눈송이 하나가 c번째 칸에 착지. 주변 칸에도 조금씩 나눠 쌓음.
    func add(at c: Int, amount: CGFloat) {
        heights[c] = min(columnCap(at: c), heights[c] + amount * 0.5)
        if c > 0 {
            heights[c - 1] = min(columnCap(at: c - 1), heights[c - 1] + amount * 0.25)
        }
        if c + 1 < heights.count {
            heights[c + 1] = min(columnCap(at: c + 1), heights[c + 1] + amount * 0.25)
        }
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

        if anyChange {
            for idx in 0..<n {
                let cap = columnCap(at: idx)
                if heights[idx] > cap {
                    heights[idx] = cap
                }
            }
            isDirty = true
        } else {
            needsRelax = false
        }
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

        if !ornaments.isEmpty {
            let topBandMinY = frame.maxY - Config.ornamentBaubleDrop - 8
            let topRelevant = occluders.filter {
                $0.minY <= frame.maxY && $0.maxY >= topBandMinY && $0.maxX > frame.minX && $0.minX < frame.maxX
            }
            var ornamentChanged = false
            for item in ornaments {
                let v = !topRelevant.contains {
                    item.x >= $0.minX && item.x <= $0.maxX && item.y >= $0.minY && item.anchorY <= $0.maxY
                }
                if v != item.isVisible {
                    item.isVisible = v
                    item.containerNode.isHidden = !v
                    ornamentChanged = true
                }
            }
            if ornamentChanged { ornamentsDirty = true }
        }
    }

    // MARK: - Drawing

    /// 보이는 칸들을 이어 부드러운 곡선 모양(path)으로 그림.
    func redraw() {
        isDirty = false
        let path = CGMutablePath()
        let shadowPath = CGMutablePath()
        let cw = Config.columnWidth
        let n = heights.count
        var c = 0

        while c < n {
            guard visible[c], heights[c] > 0.05 else { c += 1; continue }
            let start = c
            while c < n, visible[c], heights[c] > 0.05 { c += 1 }
            let end = c - 1

            let leftX = originX + CGFloat(start) * cw
            let rightX = originX + CGFloat(end + 1) * cw
            var pts: [CGPoint] = [CGPoint(x: leftX, y: base)]
            for i in start...end {
                pts.append(CGPoint(x: columnCenterX(i), y: base + heights[i]))
            }
            pts.append(CGPoint(x: rightX, y: base))

            // 점들 사이 중간점을 quad curve로 이어 각진 느낌 제거
            path.move(to: pts[0])
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2,
                                  y: (pts[i - 1].y + pts[i].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i - 1])
            }
            path.addLine(to: pts[pts.count - 1])
            path.closeSubpath()

            // 아랫부분 접촉면에 은은한 입체 그림자 선 추가
            shadowPath.move(to: CGPoint(x: leftX + 1, y: base - 0.5))
            shadowPath.addLine(to: CGPoint(x: rightX - 1, y: base - 0.5))
        }
        node.path = path
        shadowNode.path = shadowPath
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

    /// 창 상단 테두리의 가랜드 전선 곡선과 오나먼트 금색 줄/꼭지를 그림.
    func redrawOrnaments() {
        ornamentsDirty = false
        guard ornamentsEnabled, !ornaments.isEmpty else {
            garlandCordNode.path = nil
            ornamentCapNode.path = nil
            return
        }

        let cordPath = CGMutablePath()
        let capPath = CGMutablePath()

        // 짝수 인덱스는 상단 고정점(anchor), 홀수 인덱스는 처짐 곡선 중앙점(swag midpoint)
        var i = 0
        while i + 2 < ornaments.count {
            let left = ornaments[i]
            let mid = ornaments[i + 1]
            let right = ornaments[i + 2]
            if left.isVisible && mid.isVisible && right.isVisible {
                cordPath.move(to: CGPoint(x: left.x, y: left.anchorY))
                cordPath.addQuadCurve(
                    to: CGPoint(x: right.x, y: right.anchorY),
                    control: CGPoint(x: mid.x, y: left.anchorY - Config.ornamentSwagDrop * 2.0)
                )
            }
            i += 2
        }

        for item in ornaments where item.isVisible {
            if item.isBauble {
                let topOfBall = item.y + Config.ornamentBaubleRadius
                capPath.move(to: CGPoint(x: item.x, y: item.anchorY))
                capPath.addLine(to: CGPoint(x: item.x, y: topOfBall))
                capPath.addRoundedRect(
                    in: CGRect(x: item.x - 2.0, y: topOfBall - 0.6, width: 4.0, height: 2.2),
                    cornerWidth: 0.6,
                    cornerHeight: 0.6
                )
            } else {
                capPath.addRoundedRect(
                    in: CGRect(x: item.x - 1.3, y: item.anchorY - 1.2, width: 2.6, height: 1.8),
                    cornerWidth: 0.5,
                    cornerHeight: 0.5
                )
            }
        }

        garlandCordNode.path = cordPath
        ornamentCapNode.path = capPath
    }

    // MARK: - Ornament Textures

    /// 입체적인 유리 광택(하이라이트)이 들어간 방울 오나먼트 텍스처 생성
    private static func makeBaubleTexture() -> SKTexture {
        let px = 32
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }

        let rect = CGRect(x: 2, y: 2, width: px - 4, height: px - 4)
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()

        let colors = [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 0.96),
            CGColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 0.92)
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.55, 1.0]
        if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
            let lightOrigin = CGPoint(x: CGFloat(px) * 0.36, y: CGFloat(px) * 0.68)
            let center = CGPoint(x: CGFloat(px) * 0.5, y: CGFloat(px) * 0.5)
            ctx.drawRadialGradient(
                grad,
                startCenter: lightOrigin, startRadius: 1,
                endCenter: center, endRadius: CGFloat(px - 4) * 0.5,
                options: [.drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // 왼쪽 위 반짝이는 유리 하이라이트 점
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.78))
        ctx.fillEllipse(in: CGRect(x: 8, y: 18, width: 6, height: 5))

        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    /// 전구 주변으로 부드럽게 퍼지는 빛 번짐(halo) 텍스처 생성
    private static func makeGlowTexture() -> SKTexture {
        let px = 48
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }

        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.45),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.28, 0.62, 1.0]
        guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: locations) else {
            return SKTexture()
        }
        let c = CGPoint(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(px) / 2, options: [])
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    /// 전구 중심부의 밝은 필라멘트 코어 텍스처 생성
    private static func makeCoreTexture() -> SKTexture {
        let px = 20
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }

        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1.0),
            CGColor(red: 1, green: 0.98, blue: 0.90, alpha: 0.85),
            CGColor(red: 1, green: 0.95, blue: 0.80, alpha: 0.0)
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.45, 1.0]
        guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: locations) else {
            return SKTexture()
        }
        let c = CGPoint(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(px) / 2, options: [])
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }
}
