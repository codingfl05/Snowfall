import AppKit
import SpriteKit

/// Dock 영역 위로 두 눈덩이가 굴러와 쌓이고, 빨간 목도리를 두른 채 손을 흔들다가 녹아 사라지는 눈사람.
@MainActor
final class Snowman {
    private enum Phase {
        case rolling(TimeInterval)
        case stacking(TimeInterval)
        case waving(TimeInterval)
        case melting(TimeInterval)
        case finished
    }

    let rootNode = SKNode()
    let targetX: CGFloat
    let groundY: CGFloat
    private(set) var isFinished = false

    private var phase: Phase = .rolling(0)
    private let bodyNode: SKShapeNode
    private let headNode: SKShapeNode
    private let detailsNode = SKNode()
    private let rightArmPivot = SKNode()
    private let scarfTailNode: SKShapeNode

    private let rBody = Config.snowmanBodyRadius
    private let rHead = Config.snowmanHeadRadius
    private var stackedHeadY: CGFloat { rBody * 2 + rHead * 0.72 }

    init(targetX: CGFloat, groundY: CGFloat) {
        self.targetX = targetX
        self.groundY = groundY

        rootNode.position = CGPoint(x: targetX, y: groundY)
        rootNode.zPosition = 8

        // 몸통 눈덩이 (굴러가는 회전이 보이도록 작은 눈 무늬 점 포함)
        bodyNode = Snowman.makeSnowballNode(radius: rBody)
        headNode = Snowman.makeSnowballNode(radius: rHead)

        // 흔들리는 목도리 끝자락
        let tailPath = CGMutablePath()
        tailPath.addRoundedRect(in: CGRect(x: -2.2, y: -11, width: 4.4, height: 11), cornerWidth: 1.8, cornerHeight: 1.8)
        scarfTailNode = SKShapeNode(path: tailPath)
        scarfTailNode.fillColor = NSColor(calibratedRed: 0.88, green: 0.18, blue: 0.22, alpha: 1.0)
        scarfTailNode.strokeColor = NSColor(calibratedRed: 0.65, green: 0.10, blue: 0.14, alpha: 1.0)
        scarfTailNode.lineWidth = 0.7

        // 바닥 그림자 (밝은 배경/Dock 위에서도 눈사람이 뚜렷하게 보이도록 함)
        let shadowOval = SKShapeNode(ellipseOf: CGSize(width: rBody * 2.1, height: 5.5))
        shadowOval.fillColor = NSColor(calibratedRed: 0.20, green: 0.30, blue: 0.45, alpha: 0.32)
        shadowOval.strokeColor = .clear
        shadowOval.position = CGPoint(x: 0, y: 1)
        rootNode.addChild(shadowOval)

        rootNode.addChild(bodyNode)
        rootNode.addChild(headNode)
        rootNode.addChild(detailsNode)

        buildDetails()
        detailsNode.alpha = 0
        updateRolling(progress: 0)
    }

    /// 설정에서 눈사람을 끄거나 씬이 정리될 때 노드 트리를 즉시 해제하여 메모리를 반환
    func destroy() {
        detailsNode.removeAllChildren()
        bodyNode.removeAllChildren()
        headNode.removeAllChildren()
        rootNode.removeAllChildren()
        rootNode.removeFromParent()
        isFinished = true
    }

    // MARK: - Frame update

    func step(dt: TimeInterval) {
        switch phase {
        case .rolling(let elapsed):
            let next = elapsed + dt
            let p = min(1.0, CGFloat(next / Config.snowmanRollDuration))
            updateRolling(progress: p)
            if next >= Config.snowmanRollDuration {
                phase = .stacking(0)
            } else {
                phase = .rolling(next)
            }

        case .stacking(let elapsed):
            let next = elapsed + dt
            let p = min(1.0, CGFloat(next / Config.snowmanStackDuration))
            updateStacking(progress: p)
            if next >= Config.snowmanStackDuration {
                detailsNode.alpha = 1
                phase = .waving(0)
            } else {
                phase = .stacking(next)
            }

        case .waving(let elapsed):
            let next = elapsed + dt
            updateWaving(time: next)
            if next >= Config.snowmanWaveDuration {
                phase = .melting(0)
            } else {
                phase = .waving(next)
            }

        case .melting(let elapsed):
            let next = elapsed + dt
            let p = min(1.0, CGFloat(next / Config.snowmanMeltDuration))
            updateMelting(progress: p)
            if next >= Config.snowmanMeltDuration {
                destroy()
                phase = .finished
            } else {
                phase = .melting(next)
            }

        case .finished:
            isFinished = true
        }
    }

    // MARK: - Animation phases

    private func updateRolling(progress p: CGFloat) {
        // smoothstep 곡선으로 자연스럽게 감속하며 도착
        let ease = p * p * (3 - 2 * p)
        let dist = Config.snowmanRollDistance

        // 왼쪽에서 굴러오는 몸통 눈덩이
        let bodyX = -dist * (1 - ease)
        let bodyScale = 0.55 + 0.45 * ease
        bodyNode.position = CGPoint(x: bodyX, y: rBody * bodyScale)
        bodyNode.setScale(bodyScale)
        bodyNode.zRotation = -(dist * ease) / rBody

        // 오른쪽에서 굴러오는 머리 눈덩이
        let headStartDist = dist * 0.85
        let headStopX: CGFloat = rBody + rHead + 2
        let headX = headStopX + (headStartDist - headStopX) * (1 - ease)
        let headScale = 0.55 + 0.45 * ease
        headNode.position = CGPoint(x: headX, y: rHead * headScale)
        headNode.setScale(headScale)
        headNode.zRotation = ((headStartDist - headStopX) * ease) / rHead
    }

    private func updateStacking(progress p: CGFloat) {
        let ease = p * p * (3 - 2 * p)
        bodyNode.position = CGPoint(x: 0, y: rBody)
        bodyNode.setScale(1.0)

        // 머리 눈덩이가 포물선 궤적으로 점프해 몸통 위에 안착
        let startX: CGFloat = rBody + rHead + 2
        let startY: CGFloat = rHead
        let endY: CGFloat = stackedHeadY
        let arcHeight: CGFloat = 14 * 4 * p * (1 - p)

        headNode.position = CGPoint(
            x: startX * (1 - ease),
            y: startY + (endY - startY) * ease + arcHeight
        )
        headNode.zRotation *= (1 - ease)

        // 마지막 40% 구간에서 목도리, 얼굴, 나뭇가지 팔이 나타남
        if p > 0.6 {
            detailsNode.alpha = (p - 0.6) / 0.4
        }
    }

    private func updateWaving(time t: TimeInterval) {
        let ft = CGFloat(t)
        let waveAngle = sin(ft * Config.snowmanWaveSpeed) * 0.45
        rightArmPivot.zRotation = 0.35 + waveAngle
        headNode.zRotation = sin(ft * Config.snowmanWaveSpeed * 0.5) * 0.06
        scarfTailNode.zRotation = 0.12 + sin(ft * 4.0) * 0.15
    }

    private func updateMelting(progress p: CGFloat) {
        let ease = p * p * (3 - 2 * p)
        rootNode.xScale = 1.0 + 0.38 * ease
        rootNode.yScale = max(0.06, 1.0 - 0.92 * ease)
        rootNode.alpha = 1.0 - ease
    }

    // MARK: - Visual construction

    private static func makeSnowballNode(radius: CGFloat) -> SKShapeNode {
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = NSColor(white: 1.0, alpha: 0.98)
        circle.strokeColor = NSColor(calibratedRed: 0.68, green: 0.76, blue: 0.88, alpha: 0.95)
        circle.lineWidth = 1.0
        circle.isAntialiased = true

        // 굴러갈 때 회전이 잘 보이도록 은은한 눈결 무늬 추가
        let speck = SKShapeNode(circleOfRadius: radius * 0.22)
        speck.fillColor = NSColor(calibratedRed: 0.85, green: 0.90, blue: 0.97, alpha: 0.7)
        speck.strokeColor = .clear
        speck.position = CGPoint(x: radius * 0.38, y: radius * 0.25)
        circle.addChild(speck)
        return circle
    }

    private func buildDetails() {
        let neckY = rBody * 2 - 1.5
        let headCenterY = stackedHeadY

        // 1. 나뭇가지 왼팔 (고정)
        let leftArmPath = CGMutablePath()
        leftArmPath.move(to: CGPoint(x: -rBody + 2, y: rBody * 1.25))
        leftArmPath.addLine(to: CGPoint(x: -rBody - 11, y: rBody * 1.55))
        leftArmPath.move(to: CGPoint(x: -rBody - 7, y: rBody * 1.44))
        leftArmPath.addLine(to: CGPoint(x: -rBody - 9, y: rBody * 1.72))
        let leftArm = SKShapeNode(path: leftArmPath)
        leftArm.strokeColor = NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.14, alpha: 0.95)
        leftArm.lineWidth = 1.8
        leftArm.lineCap = .round
        detailsNode.addChild(leftArm)

        // 2. 나뭇가지 오른팔 (손 흔들기용 회전축)
        rightArmPivot.position = CGPoint(x: rBody - 2, y: rBody * 1.25)
        let rightArmPath = CGMutablePath()
        rightArmPath.move(to: .zero)
        rightArmPath.addLine(to: CGPoint(x: 12, y: 5))
        rightArmPath.move(to: CGPoint(x: 8, y: 3.3))
        rightArmPath.addLine(to: CGPoint(x: 10, y: 8.5))
        let rightArm = SKShapeNode(path: rightArmPath)
        rightArm.strokeColor = NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.14, alpha: 0.95)
        rightArm.lineWidth = 1.8
        rightArm.lineCap = .round
        rightArmPivot.addChild(rightArm)
        detailsNode.addChild(rightArmPivot)

        // 3. 몸통 단추 2개
        for btnY in [rBody * 1.28, rBody * 0.82] {
            let button = SKShapeNode(circleOfRadius: 1.5)
            button.fillColor = NSColor(white: 0.18, alpha: 0.95)
            button.strokeColor = .clear
            button.position = CGPoint(x: 0, y: btnY)
            detailsNode.addChild(button)
        }

        // 4. 빨간 목도리 (목 둘레 + 아래로 늘어진 자락)
        let scarfWrapRect = CGRect(x: -rHead * 0.92, y: neckY - 2.4, width: rHead * 1.84, height: 4.8)
        let scarfWrapPath = CGPath(roundedRect: scarfWrapRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
        let scarfWrap = SKShapeNode(path: scarfWrapPath)
        scarfWrap.fillColor = NSColor(calibratedRed: 0.90, green: 0.20, blue: 0.24, alpha: 1.0)
        scarfWrap.strokeColor = NSColor(calibratedRed: 0.65, green: 0.10, blue: 0.14, alpha: 1.0)
        scarfWrap.lineWidth = 0.7
        detailsNode.addChild(scarfWrap)

        scarfTailNode.position = CGPoint(x: rHead * 0.38, y: neckY - 1.0)
        detailsNode.addChild(scarfTailNode)

        // 5. 눈 두 개
        for eyeX in [-rHead * 0.34, rHead * 0.34] {
            let eye = SKShapeNode(circleOfRadius: 1.4)
            eye.fillColor = NSColor(white: 0.12, alpha: 1.0)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: eyeX, y: headCenterY + rHead * 0.18)
            detailsNode.addChild(eye)
        }

        // 6. 주황색 당근 코
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: 0, y: headCenterY + 1.2))
        nosePath.addLine(to: CGPoint(x: 6.5, y: headCenterY - 0.5))
        nosePath.addLine(to: CGPoint(x: 0, y: headCenterY - 1.8))
        nosePath.closeSubpath()
        let nose = SKShapeNode(path: nosePath)
        nose.fillColor = NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.14, alpha: 1.0)
        nose.strokeColor = NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.06, alpha: 0.9)
        nose.lineWidth = 0.5
        detailsNode.addChild(nose)
    }
}
