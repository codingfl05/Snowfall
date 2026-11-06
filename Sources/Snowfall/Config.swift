import CoreGraphics
import Foundation

/// 모든 tuning 값은 여기에 모아둠.
/// 눈의 "느낌"을 바꾸고 싶으면 로직 대신 이 파일의 숫자부터 바꿔볼 것.
enum Config {
    // MARK: - Rendering
    static let framesPerSecond = 30                  // 기본 FPS (30 또는 60)
    static let availableFrameRates = [30, 60]

    // MARK: - Falling flakes (내리는 눈)
    static let maxFlakes = 4000
    static let flakeRadiusRange: ClosedRange<CGFloat> = 1.4...3.6
    static let baseFallSpeed: CGFloat = 26           // pt/s
    static let fallSpeedPerRadius: CGFloat = 11      // 큰 눈송이일수록 빨리 떨어짐
    static let swayAmplitude: CGFloat = 16           // 좌우 흔들림 세기 (pt/s)
    static let swayFrequencyRange: ClosedRange<CGFloat> = 0.6...1.6   // rad/s
    static let wind: CGFloat = 5                     // 일정한 바람 (+ 값이면 오른쪽)
    static let flakeAlphaRange: ClosedRange<CGFloat> = 0.7...1.0

    // MARK: - Accumulation (쌓이기)
    static let columnWidth: CGFloat = 3              // heightmap 한 칸의 폭 (pt)
    static let accumulationPerFlake: CGFloat = 0.3   // 눈송이 하나가 쌓이는 양 (× radius)
    static let maxPileHeight: CGFloat = 18           // 최대 쌓이는 높이 (pt)
    static let maxSlope: CGFloat = 1.0               // 인접 칸 높이 차 한계 (angle of repose)
    static let relaxPassesPerFrame = 3
    static let pileEdgeInset: CGFloat = 12           // macOS 26 둥근 모서리만큼 양 끝을 비움
    static let spillPerFlake: CGFloat = 0.6          // 가장자리로 흘러넘친 양이 이만큼 모이면 눈송이 하나 떨어짐

    // MARK: - Window tracking (창 감지)
    static let windowPollInterval: TimeInterval = 0.05   // 20 Hz
    static let moveThreshold: CGFloat = 0.5              // 이 이상 움직이면 "창이 움직였다"로 판단
    static let minWindowSize = CGSize(width: 80, height: 40)

    // MARK: - Snow sliding off (창을 움직이면 떨어지는 눈 = debris)
    static let maxDebrisPerDump = 300
    static let debrisLandDelay: TimeInterval = 0.35  // 떨어진 직후 바로 다시 쌓이지 않도록
    static let debrisTerminalSpeed: CGFloat = 260
    static let debrisAcceleration: CGFloat = 1.2     // 클수록 빨리 최고 속도 도달
    static let debrisMass: CGFloat = 2.5             // 다른 창에 떨어질 때 쌓이는 양 배율

    // MARK: - Icicles (고드름)
    static let icicleStartDelay: TimeInterval = 5.0                  // 창이 가만히 있으면 고드름이 자라기 시작하는 시간 (초)
    static let iciclesPer100pt: Double = 2.5                         // 창 폭 100pt당 고드름 개수
    static let icicleMinSpacing: CGFloat = 14                        // 고드름 간 최소 간격 (pt)
    static let icicleEdgeInset: CGFloat = 16                         // 창 양 끝 둥근 모서리 여백 (pt)
    static let icicleBaseWidthRange: ClosedRange<CGFloat> = 3.5...7.0 // 고드름 뿌리 폭 범위 (pt)
    static let icicleMaxLengthRange: ClosedRange<CGFloat> = 14...38  // 고드름 최대 길이 범위 (pt)
    static let icicleGrowthSpeedRange: ClosedRange<CGFloat> = 2.0...4.5 // 초당 자라는 속도 (pt/s)
    static let icicleStaggerRange: ClosedRange<TimeInterval> = 0...2.5  // 고드름마다 자라기 시작하는 시간차 (초)

    // MARK: - Dock & Desktop icons (Accessibility)
    static let axPollInterval: TimeInterval = 0.25                   // Dock/바탕화면 아이콘 위치 갱신 주기 (4 Hz)
    static let minIconSize = CGSize(width: 24, height: 24)
    static let maxIconSize = CGSize(width: 220, height: 220)
    static let iconEdgeInset: CGFloat = 4                            // 아이콘 양 끝 여백 (pt)
    static let maxIconPileHeight: CGFloat = 10                       // 아이콘 위에 쌓이는 최대 눈 높이 (pt)

    // MARK: - Snowman (눈사람)
    static let snowmanFirstDelay: TimeInterval = 8.0                 // 앱 실행 후 첫 눈사람 등장 시간 (초)
    static let snowmanIntervalRange: ClosedRange<TimeInterval> = 35.0...65.0 // 다음 눈사람 등장 간격 (초)
    static let snowmanRollDuration: TimeInterval = 2.2               // 눈덩이가 굴러오는 시간 (초)
    static let snowmanRollDistance: CGFloat = 105                    // 눈덩이가 굴러오는 거리 (pt)
    static let snowmanStackDuration: TimeInterval = 0.7              // 머리 눈덩이가 위로 올라가는 시간 (초)
    static let snowmanWaveDuration: TimeInterval = 6.0               // 목도리를 두르고 손을 흔드는 시간 (초)
    static let snowmanWaveSpeed: CGFloat = 7.5                       // 손 흔드는 속도 (rad/s)
    static let snowmanMeltDuration: TimeInterval = 3.0               // 눈사람이 녹아 사라지는 시간 (초)
    static let snowmanBodyRadius: CGFloat = 14                       // 몸통 눈덩이 반지름 (pt)
    static let snowmanHeadRadius: CGFloat = 9.5                      // 머리 눈덩이 반지름 (pt)
    static let snowmanDefaultDockHeight: CGFloat = 76                // Dock 감지 전 기본 Dock 높이 (pt)

    // MARK: - Debug
    /// 터미널에서 `SNOW_DEBUG=1 swift run -c release` 로 실행하면 감지된 창 수 등을 출력
    static let debugLogging = ProcessInfo.processInfo.environment["SNOW_DEBUG"] != nil
}

enum SnowIntensity: String, CaseIterable {
    case light, normal, blizzard

    var title: String {
        switch self {
        case .light: return "Light"
        case .normal: return "Normal"
        case .blizzard: return "Blizzard"
        }
    }

    /// 화면 폭 1000pt 당 초당 생성되는 눈송이 수
    var flakesPerSecondPer1000pt: Double {
        switch self {
        case .light: return 20
        case .normal: return 55
        case .blizzard: return 140
        }
    }
}
