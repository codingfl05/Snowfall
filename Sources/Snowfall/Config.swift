import CoreGraphics
import Foundation

/// 모든 tuning 값은 여기에 모아둠.
/// 눈의 "느낌"을 바꾸고 싶으면 로직 대신 이 파일의 숫자부터 바꿔볼 것.
enum Config {
    // MARK: - Rendering
    static let framesPerSecond = 30                  // 기본 FPS (30 또는 60)
    static let availableFrameRates = [30, 60]

    // MARK: - Falling flakes (내리는 눈)
    static let defaultSnowEnabled = true             // 눈 내리기 기능 기본값
    static let maxFlakes = 4000
    static let flakeRadiusRange: ClosedRange<CGFloat> = 1.1...4.0
    static let baseFallSpeed: CGFloat = 24           // pt/s
    static let fallSpeedPerRadius: CGFloat = 12      // 큰 눈송이(근경)일수록 빨리 떨어져 깊이감 형성
    static let swayAmplitude: CGFloat = 16           // 좌우 흔들림 세기 (pt/s)
    static let swayFrequencyRange: ClosedRange<CGFloat> = 0.6...1.6   // rad/s
    static let wind: CGFloat = 5                     // 일정한 바람 (+ 값이면 오른쪽)
    static let flakeAlphaRange: ClosedRange<CGFloat> = 0.38...0.98    // 원경(반투명)~근경(선명) 입체감

    // MARK: - Accumulation (쌓이기)
    static let columnWidth: CGFloat = 3              // heightmap 한 칸의 폭 (pt)
    static let accumulationPerFlake: CGFloat = 0.3   // 눈송이 하나가 쌓이는 양 (× radius)
    static let maxPileHeight: CGFloat = 18           // 최대 쌓이는 높이 (pt)
    static let maxSlope: CGFloat = 0.85              // 인접 칸 높이 차 한계 (작을수록 완만하고 폭신한 곡선)
    static let pileTaperColumns = 4                  // 양 끝이 둥글게 낮아지는 칸 수 (벽돌 모양 방지)
    static let relaxPassesPerFrame = 3
    static let pileEdgeInset: CGFloat = 12           // macOS 26 둥근 모서리만큼 양 끝을 비움
    static let spillPerFlake: CGFloat = 0.6          // 가장자리로 흘러넘친 양이 이만큼 모이면 눈송이 하나 떨어짐

    // MARK: - Window tracking (창 감지)
    static let windowPollInterval: TimeInterval = 0.05   // 20 Hz
    static let fullscreenPollInterval: TimeInterval = 0.25 // 전체화면 상태 확인 주기 (4 Hz)
    static let moveThreshold: CGFloat = 0.5              // 이 이상 움직이면 "창이 움직였다"로 판단
    static let minWindowSize = CGSize(width: 220, height: 120) // 스테이지 매니저 썸네일 등 작은 보조 창 제외
    static let stageManagerStripWidth: CGFloat = 195     // 화면 왼쪽 스테이지 매니저 프리뷰 영역 폭 (pt)

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
    static let axPollInterval: TimeInterval = 0.25                   // Dock 아이콘 위치 갱신 주기 (4 Hz)
    static let axDesktopPollInterval: TimeInterval = 1.0             // Finder 바탕화면 아이콘 위치 갱신 주기 (1 Hz)
    static let axMessagingTimeout: Float = 0.1                       // AX IPC 응답 대기 상한 (초)
    static let minIconSize = CGSize(width: 24, height: 24)
    static let maxIconSize = CGSize(width: 220, height: 220)
    static let iconEdgeInset: CGFloat = 5                            // Dock 아이콘 양 끝 여백 (pt)
    static let desktopIconEdgeInset: CGFloat = 13                    // 바탕화면 폴더 아이콘 좌우 여백 (실제 폴더 폭에 맞춤)
    static let desktopIconTopOffset: CGFloat = 9                     // 바탕화면 아이콘 셀 상단 빈 여백 보정 (폴더 윗변에 밀착)
    static let maxIconPileHeight: CGFloat = 8.5                      // 아이콘 위에 쌓이는 최대 눈 높이 (pt)

    // MARK: - Snowman (눈사람)
    static let defaultSnowmanEnabled = true                          // 눈사람 표시 기본값
    static let snowmanFirstDelay: TimeInterval = 8.0                 // 앱 실행 후 첫 눈사람 등장 시간 (초)
    static let snowmanIntervalRange: ClosedRange<TimeInterval> = 35.0...65.0 // 다음 눈사람 등장 간격 (초)
    static let snowmanRollDuration: TimeInterval = 2.2               // 눈덩이가 굴러오는 시간 (초)
    static let snowmanRollDistance: CGFloat = 105                    // 눈덩이가 굴러오는 거리 (pt)
    static let snowmanStackDuration: TimeInterval = 0.7              // 머리 눈덩이가 위로 올라가는 시간 (초)
    static let snowmanWaveDuration: TimeInterval = 6.0               // 목도리를 두르고 손을 흔드는 시간 (초)
    static let snowmanWaveSpeed: CGFloat = 7.5                       // 손 흔드는 속도 (rad/s)
    static let snowmanMeltDuration: TimeInterval = 3.0               // 눈사람이 녹아 사라지는 시간 (초)
    static let snowmanBodyRadius: CGFloat = 16                       // 몸통 눈덩이 반지름 (pt)
    static let snowmanHeadRadius: CGFloat = 11                       // 머리 눈덩이 반지름 (pt)
    static let snowmanDefaultDockHeight: CGFloat = 76                // Dock 감지 전 기본 Dock 높이 (pt)

    // MARK: - Christmas Ornaments & CPU Load (크리스마스 오나먼트 & CPU 연동 전구)
    static let defaultOrnamentsEnabled = true                        // 크리스마스 장식 표시 기본값
    static let cpuPollInterval: TimeInterval = 1.0                   // 시스템 CPU 사용량 측정 주기 (초)
    static let cpuSmoothingFactor: Double = 0.35                     // CPU 부하 지수 이동평균(EMA) 반영 비율
    static let cpuOverloadThreshold: Double = 0.65                   // 과부하로 판단해 반짝임 강도를 높이는 기준 (0.0~1.0)
    static let ornamentMinBlinkSpeed: Double = 1.8                   // 평상시(유휴 상태) 전구 숨쉬기 속도 (rad/s)
    static let ornamentMaxBlinkSpeed: Double = 16.0                  // CPU 과부하 시 전구 점멸 최고 속도 (rad/s)
    static let ornamentEdgeInsetLeft: CGFloat = 78                   // 창 왼쪽 상단 신호등 버튼(닫기/최소화/확대) 회피 여백 (pt)
    static let ornamentEdgeInsetRight: CGFloat = 22                  // 창 오른쪽 상단 모서리 여백 (pt)
    static let ornamentMinWindowWidth: CGFloat = 260                 // 장식을 달기 위한 최소 창 폭 (pt)
    static let ornamentSpacing: CGFloat = 52                         // 가랜드 전구/오나먼트 간격 (pt)
    static let ornamentSwagDrop: CGFloat = 7.5                       // 가랜드 전선이 아래로 처지는 깊이 (pt)
    static let ornamentBaubleDrop: CGFloat = 13.0                    // 매달린 방울 오나먼트 줄 길이 (pt)
    static let ornamentBulbRadius: CGFloat = 3.2                     // 꼬마전구 반지름 (pt)
    static let ornamentBaubleRadius: CGFloat = 5.4                   // 방울 오나먼트 반지름 (pt)
    static let ornamentGlowScaleRange: ClosedRange<CGFloat> = 0.75...1.45 // 전구 빛 번짐(halo) 크기 변화 범위

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
