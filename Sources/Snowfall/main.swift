import AppKit

// 앱 진입점 (entry point).
// MainActor.assumeIsolated: 이 코드는 main thread에서 실행되므로 AppKit API를 바로 호출해도 안전하다고 컴파일러에 알려줌.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 메뉴바에만 표시
    app.run()                              // 앱 종료 전까지 여기서 멈춰 있음
}
