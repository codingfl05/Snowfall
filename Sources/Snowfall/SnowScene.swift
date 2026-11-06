import SpriteKit
import AppKit

/// 눈 시뮬레이션 전체를 담당하는 SpriteKit scene.
/// 매 frame: 창 위치 갱신(20Hz) → 눈송이 생성 → 이동/착지 → 쌓인 눈 정리 → 다시 그리기
final class SnowScene: SKScene {
    var tracker: WindowTracker?
    var intensity: SnowIntensity = .normal

    private var flakeTexture: SKTexture?
    private var active: [Flake] = []
    private var pool: [Flake] = []
    private var piles: [CGWindowID: Pile] = [:]
    private var pileOrder: [Pile] = []          // 앞(front)에 있는 창부터
    private var lastUpdate: TimeInterval = 0
    private var clock: TimeInterval = 0
    private var pollTimer: TimeInterval = 0
    private var spawnCarry: Double = 0
    private var lastDebugLog: TimeInterval = 0
    private var didPrefill = false

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        if flakeTexture == nil { flakeTexture = SnowScene.makeFlakeTexture() }
        if !didPrefill {
            prefillSky()
            didPrefill = true
        }
    }

    // MARK: - Main loop

    override func update(_ currentTime: TimeInterval) {
        // dt: 지난 frame 이후 흐른 시간. 일시정지 후 재개 시 튀지 않도록 상한을 둠.
        let dt = lastUpdate == 0 ? 1.0 / 60.0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime
        clock += dt

        pollTimer += dt
        if pollTimer >= Config.windowPollInterval {
            pollTimer = 0
            refreshWindows()
        }

        spawnFlakes(dt: dt)
        stepFlakes(dt: dt)

        for pile in pileOrder {
            pile.relax()
            emitSpill(from: pile)
            if pile.isDirty { pile.redraw() }

            pile.stepIcicles(dt: dt)
            if pile.iciclesDirty { pile.redrawIcicles() }
        }
    }

    // MARK: - Public controls

    /// 메뉴의 "쌓인 눈 털기": 모든 창의 눈과 고드름을 떨어뜨림
    func shakeOffAllSnow() {
        for pile in pileOrder {
            dumpSnow(from: pile)
            dumpIcicles(from: pile)
        }
    }

    /// 해상도/디스플레이 구성이 바뀌었을 때 전부 초기화
    func resetForScreenChange() {
        for pile in piles.values { pile.node.removeFromParent() }
        piles.removeAll()
        pileOrder.removeAll()
        recycleAllFlakes()
        prefillSky()
    }

    // MARK: - Windows

    private func refreshWindows() {
        guard let tracker else { return }
        let windows = tracker.currentWindows()
        var seen = Set<CGWindowID>()
        var order: [Pile] = []
        order.reserveCapacity(windows.count)

        for w in windows {
            seen.insert(w.id)
            if let pile = piles[w.id] {
                if pile.hasMoved(to: w.frame) {
                    // 창을 움직이면 쌓인 눈과 고드름이 미끄러져/부러져 떨어짐
                    dumpSnow(from: pile)
                    dumpIcicles(from: pile)
                    pile.reset(frame: w.frame)
                } else if pile.hasBottomMoved(to: w.frame) {
                    // 아랫변만 움직인 경우 (창 아래쪽 크기 조절) → 고드름만 부러져 떨어짐
                    dumpIcicles(from: pile)
                    pile.updateFrame(w.frame, resetIcicles: true)
                } else {
                    pile.updateFrame(w.frame, resetIcicles: false)
                }
                order.append(pile)
            } else {
                let pile = Pile(windowID: w.id, frame: w.frame, kind: w.kind)
                addChild(pile.node)
                piles[w.id] = pile
                order.append(pile)
            }
        }

        // 닫히거나 최소화된 창 → 눈과 고드름이 전부 떨어짐
        for (id, pile) in piles where !seen.contains(id) {
            dumpSnow(from: pile)
            dumpIcicles(from: pile)
            pile.node.removeFromParent()
            piles[id] = nil
        }

        // 가려짐(occlusion) 계산: 각 창은 자기보다 앞에 있는 창들에 의해 가려질 수 있음
        var frontRects: [CGRect] = []
        for pile in order {
            pile.updateVisibility(occluders: frontRects)
            frontRects.append(pile.frame)
        }
        pileOrder = order

        if Config.debugLogging && clock - lastDebugLog > 2 {
            lastDebugLog = clock
            print("[Snowfall] windows: \(windows.count), flakes: \(active.count)")
        }
    }

    // MARK: - Flakes

    private func obtainFlake() -> Flake? {
        guard active.count < Config.maxFlakes else { return nil }
        let flake: Flake
        if let reused = pool.popLast() {
            flake = reused
        } else {
            flake = Flake(texture: flakeTexture ?? SKTexture())
            addChild(flake.node)
        }
        flake.node.isHidden = false
        active.append(flake)
        return flake
    }

    private func recycle(at index: Int) {
        let flake = active[index]
        flake.node.isHidden = true
        active.swapAt(index, active.count - 1)
        active.removeLast()
        pool.append(flake)
    }

    private func recycleAllFlakes() {
        for flake in active { flake.node.isHidden = true }
        pool.append(contentsOf: active)
        active.removeAll()
    }

    private func prefillSky() {
        // 시작하자마자 화면이 비어 있지 않도록 미리 눈송이를 뿌려둠
        let avgSpeed = Config.baseFallSpeed + 2.5 * Config.fallSpeedPerRadius
        let lifetime = Double(size.height / avgSpeed)
        let count = Int(intensity.flakesPerSecondPer1000pt * Double(size.width) / 1000 * lifetime)
        for _ in 0..<min(count, Config.maxFlakes / 2) {
            spawnFlake(atY: CGFloat.random(in: 0...max(1, size.height)))
        }
    }

    private func spawnFlakes(dt: TimeInterval) {
        let rate = intensity.flakesPerSecondPer1000pt * Double(size.width) / 1000
        spawnCarry += rate * dt
        while spawnCarry >= 1 {
            spawnCarry -= 1
            spawnFlake(atY: nil)
        }
    }

    private func spawnFlake(atY y: CGFloat?) {
        guard let f = obtainFlake() else { return }
        let r = CGFloat.random(in: Config.flakeRadiusRange)
        f.setRadius(r)
        f.x = CGFloat.random(in: -30...(size.width + 10))
        f.y = y ?? (size.height + r * 2 + CGFloat.random(in: 0...20))
        f.terminalSpeed = Config.baseFallSpeed + r * Config.fallSpeedPerRadius
        f.vy = -f.terminalSpeed
        f.vx = 0
        f.acceleration = 4
        f.swayScale = CGFloat.random(in: 0.5...1.0)
        f.swayFrequency = CGFloat.random(in: Config.swayFrequencyRange)
        f.phase = CGFloat.random(in: 0...(2 * .pi))
        f.mass = 1
        f.landDelay = 0
        f.node.alpha = CGFloat.random(in: Config.flakeAlphaRange)
        f.node.position = CGPoint(x: f.x, y: f.y)
    }

    /// 창에서 떨어지는 눈 덩어리 (중력처럼 점점 빨라짐)
    private func spawnDebris(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat) {
        guard let f = obtainFlake() else { return }
        f.setRadius(CGFloat.random(in: 1.6...3.2))
        f.x = x
        f.y = y
        f.vx = vx
        f.vy = vy
        f.terminalSpeed = Config.debrisTerminalSpeed
        f.acceleration = Config.debrisAcceleration
        f.swayScale = 0.25
        f.swayFrequency = CGFloat.random(in: Config.swayFrequencyRange)
        f.phase = CGFloat.random(in: 0...(2 * .pi))
        f.mass = Config.debrisMass
        f.landDelay = Config.debrisLandDelay
        f.node.alpha = 1
        f.node.position = CGPoint(x: x, y: y)
    }

    private func stepFlakes(dt: TimeInterval) {
        let fdt = CGFloat(dt)
        let t = CGFloat(clock)
        var i = 0
        while i < active.count {
            let f = active[i]
            let prevY = f.y

            f.vy += (-f.terminalSpeed - f.vy) * min(1, f.acceleration * fdt)
            f.vx *= max(0, 1 - 1.5 * fdt)   // 옆으로 튄 속도는 서서히 감소
            let sway = sin(t * f.swayFrequency + f.phase) * Config.swayAmplitude * f.swayScale
            f.x += (f.vx + sway + Config.wind) * fdt
            f.y += f.vy * fdt
            if f.landDelay > 0 { f.landDelay -= dt }

            var remove = false
            if f.landDelay <= 0 && land(f, prevY: prevY) {
                remove = true
            } else if f.y < -20 || f.x < -60 || f.x > size.width + 60 {
                remove = true
            }

            if remove {
                recycle(at: i)   // swap-remove: i 자리에 다른 눈송이가 들어오므로 i는 그대로
            } else {
                f.node.position = CGPoint(x: f.x, y: f.y)
                i += 1
            }
        }
    }

    /// 이번 frame에 눈송이가 어떤 창의 눈 표면을 "통과"했으면 착지 처리
    private func land(_ f: Flake, prevY: CGFloat) -> Bool {
        for pile in pileOrder {
            guard let c = pile.column(atX: f.x), pile.visible[c] else { continue }
            let surface = pile.base + pile.heights[c]
            if prevY >= surface && f.y < surface {
                pile.add(at: c, amount: f.radius * Config.accumulationPerFlake * f.mass)
                return true
            }
        }
        return false
    }

    // MARK: - Snow falling off

    /// 창에 쌓인 눈을 debris 눈송이로 바꿔 떨어뜨림
    private func dumpSnow(from pile: Pile) {
        guard pile.totalSnow > 0.5 else { pile.clear(); return }
        var budget = Config.maxDebrisPerDump
        var c = 0
        while c < pile.heights.count && budget > 0 {
            let h = pile.heights[c]
            if pile.visible[c] && h > 0.4 {
                let pieces = min(3, Int(h / 4) + 1)
                for _ in 0..<pieces where budget > 0 {
                    spawnDebris(
                        x: pile.columnCenterX(c) + CGFloat.random(in: -1...1),
                        y: pile.base + CGFloat.random(in: 0...h),
                        vx: CGFloat.random(in: -30...30),
                        vy: CGFloat.random(in: -10...40)
                    )
                    budget -= 1
                }
            }
            c += 2   // 모든 칸이 아니라 한 칸 건너 생성 (개수 절약)
        }
        pile.clear()
    }

    /// 창을 움직이거나 닫을 때 아랫변의 고드름이 부러져 debris처럼 떨어짐
    private func dumpIcicles(from pile: Pile) {
        let topY = pile.bottomBase
        for icicle in pile.icicles where icicle.isVisible && icicle.length > 1.5 {
            let pieces = max(1, Int(icicle.length / 6))
            for _ in 0..<pieces {
                spawnDebris(
                    x: icicle.x + CGFloat.random(in: -1.5...1.5),
                    y: topY - CGFloat.random(in: 0...icicle.length),
                    vx: CGFloat.random(in: -22...22),
                    vy: CGFloat.random(in: -40 ... -5)
                )
            }
        }
        pile.seedIcicles()
        pile.redrawIcicles()
    }

    /// 양 끝으로 흘러넘친 눈을 작은 눈송이로 떨어뜨림
    private func emitSpill(from pile: Pile) {
        let n = pile.heights.count
        guard n > 0 else { return }
        while pile.spillLeft >= Config.spillPerFlake {
            pile.spillLeft -= Config.spillPerFlake
            if pile.visible[0] {
                spawnDebris(x: pile.originX - 1, y: pile.base + 1,
                            vx: -CGFloat.random(in: 4...16), vy: 0)
            }
        }
        while pile.spillRight >= Config.spillPerFlake {
            pile.spillRight -= Config.spillPerFlake
            if pile.visible[n - 1] {
                spawnDebris(x: pile.endX + 1, y: pile.base + 1,
                            vx: CGFloat.random(in: 4...16), vy: 0)
            }
        }
    }

    // MARK: - Texture

    /// 눈송이 이미지를 코드로 생성: 가운데는 흰색, 가장자리는 옅은 회청색으로 투명하게 번짐
    /// (흰 배경 위에서도 눈송이가 보이도록)
    static func makeFlakeTexture() -> SKTexture {
        let px = 32
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SKTexture() }

        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
            CGColor(red: 0.70, green: 0.76, blue: 0.86, alpha: 0.55),
            CGColor(red: 0.70, green: 0.76, blue: 0.86, alpha: 0)
        ] as CFArray
        let locations: [CGFloat] = [0, 0.45, 0.7, 1]
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else {
            return SKTexture()
        }
        let center = CGPoint(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: CGFloat(px) / 2,
                               options: [])
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }
}
