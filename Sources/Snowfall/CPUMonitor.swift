import Darwin
import Foundation

/// 시스템 전체 CPU 사용률(0.0 ~ 1.0)을 주기적으로 측정하여
/// 크리스마스 오나먼트 전구의 점멸 속도(blink speed)를 결정하는 모니터.
@MainActor
final class CPUMonitor {
    static let shared = CPUMonitor()

    /// 부드럽게 보정된 현재 CPU 부하 (0.0 = 완전 유휴, 1.0 = 모든 코어 100% 사용)
    private(set) var load: Double = 0.1
    private var prevUser: UInt32 = 0
    private var prevSystem: UInt32 = 0
    private var prevIdle: UInt32 = 0
    private var prevNice: UInt32 = 0
    private var hasSampled = false
    private var lastSampleTime: TimeInterval = -999

    private init() {
        sampleTicks()
    }

    /// 현재 CPU 부하에 비례하는 전구 점멸 속도 (rad/s)
    var currentBlinkSpeed: Double {
        // 부하가 높을수록 비선형(거듭제곱)으로 더 빠르게 깜빡여 과부하 상태를 직관적으로 표현
        let curved = pow(max(0, min(1, load)), 1.25)
        return Config.ornamentMinBlinkSpeed
            + (Config.ornamentMaxBlinkSpeed - Config.ornamentMinBlinkSpeed) * curved
    }

    /// 과부하 구간(cpuOverloadThreshold 이상)에 진입했는지 여부 (0.0 ~ 1.0 강도)
    var overloadIntensity: Double {
        guard load > Config.cpuOverloadThreshold else { return 0 }
        let span = max(0.05, 1.0 - Config.cpuOverloadThreshold)
        return min(1.0, (load - Config.cpuOverloadThreshold) / span)
    }

    /// 매 프레임 호출하되, 실제로는 Config.cpuPollInterval(1초)마다 한 번씩만 커널 통계를 읽음
    func updateIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastSampleTime >= Config.cpuPollInterval else { return }
        lastSampleTime = currentTime
        sampleTicks()
    }

    /// Mach 커널의 host_statistics(HOST_CPU_LOAD_INFO)를 호출해
    /// 직전 측정 시점 이후 누적된 CPU tick 변화량(user + system + nice / total)을 계산.
    private func sampleTicks() {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = info.cpu_ticks.0     // CPU_STATE_USER
        let system = info.cpu_ticks.1   // CPU_STATE_SYSTEM
        let idle = info.cpu_ticks.2     // CPU_STATE_IDLE
        let nice = info.cpu_ticks.3     // CPU_STATE_NICE

        if hasSampled {
            let dUser = user &- prevUser
            let dSystem = system &- prevSystem
            let dIdle = idle &- prevIdle
            let dNice = nice &- prevNice
            let total = UInt64(dUser) + UInt64(dSystem) + UInt64(dIdle) + UInt64(dNice)
            if total > 0 {
                let busy = Double(UInt64(dUser) + UInt64(dSystem) + UInt64(dNice))
                let rawLoad = min(1.0, max(0.0, busy / Double(total)))
                let alpha = Config.cpuSmoothingFactor
                load = load * (1.0 - alpha) + rawLoad * alpha
            }
        } else {
            hasSampled = true
        }

        prevUser = user
        prevSystem = system
        prevIdle = idle
        prevNice = nice
    }
}
