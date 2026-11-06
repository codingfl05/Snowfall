import SpriteKit

/// 눈송이 하나. 매번 새로 만들지 않고 pool에서 재사용함 (성능).
@MainActor
final class Flake {
    let node: SKSpriteNode
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var radius: CGFloat = 2
    var terminalSpeed: CGFloat = 40      // 최고 낙하 속도
    var acceleration: CGFloat = 4        // vy가 terminalSpeed에 다가가는 속도
    var swayScale: CGFloat = 1
    var swayFrequency: CGFloat = 1
    var phase: CGFloat = 0
    var mass: CGFloat = 1                // 쌓일 때 양 배율
    var landDelay: TimeInterval = 0      // 0보다 크면 아직 착지 불가

    init(texture: SKTexture) {
        node = SKSpriteNode(texture: texture)
        node.zPosition = 10
    }

    func setRadius(_ r: CGFloat) {
        radius = r
        // texture 가장자리가 투명하게 퍼지므로, 실제 보이는 크기 ≈ 지름 2r
        let d = r * 3.2
        node.size = CGSize(width: d, height: d)
    }
}
