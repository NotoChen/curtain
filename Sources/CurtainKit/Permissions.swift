import AppKit
import ApplicationServices
import CoreGraphics

/// 两项系统权限的检测与引导跳转。
/// - 辅助功能：建 CGEventTap 用
/// - 屏幕录制：SCK 截图/录屏用
public enum Permissions {
    public static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统「是否允许控制这台电脑」的弹窗，并把 app 加进辅助功能列表。
    public static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 触发系统的屏幕录制授权，并把 app 加进列表。
    @discardableResult
    public static func promptScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
