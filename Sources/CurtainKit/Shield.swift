import AppKit
import CoreGraphics

/// 幕帘窗口：每块屏幕一个黑色无边框窗口，位于 shielding 层级，
/// `sharingType = .none` 让它在截图/录屏里完全消失，但人眼照常看到。
public final class Shield {
    private var windows: [NSWindow] = []
    public private(set) var isUp = false

    private let shieldingLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    /// 认证面板要显示在幕帘之上：降到屏保层级（高于所有应用窗口，低于系统面板）。
    private let demotedLevel = NSWindow.Level(rawValue: 1000)

    public init() {}

    public func raise() {
        guard !isUp else { return }
        build()
        isUp = true
        CGDisplayHideCursor(CGMainDisplayID())
    }

    public func lower() {
        guard isUp else { return }
        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
        isUp = false
        CGDisplayShowCursor(CGMainDisplayID())
    }

    public func demoteForAuth() {
        for w in windows { w.level = demotedLevel }
    }

    public func restoreLevel() {
        for w in windows { w.level = shieldingLevel }
    }

    /// 显示器热插拔/分辨率变化时重建，避免只盖住其中一块。
    public func rebuildIfNeeded() {
        guard isUp else { return }
        let screens = NSScreen.screens
        if screens.count != windows.count {
            for w in windows { w.orderOut(nil); w.close() }
            windows.removeAll()
            build()
            return
        }
        for (w, s) in zip(windows, screens) where w.frame != s.frame {
            w.setFrame(s.frame, display: true)
        }
    }

    private func build() {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = shieldingLevel
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.sharingType = .none
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}
