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

    public static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
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
