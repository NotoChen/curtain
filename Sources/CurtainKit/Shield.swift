import AppKit
import CoreGraphics

/// 幕帘：默认把显示器 gamma 设为统一纯色，黑在输出层，framebuffer 采集不受影响。
/// 认证时需要让系统 Touch ID 面板显形，才临时恢复 gamma 并用黑色窗口盖住桌面。
public final class Shield {
    private var authWindows: [CGDirectDisplayID: NSWindow] = [:]
    public private(set) var isUp = false
    /// 输出层纯色失效时在主线程回调；调用方必须撤幕，而不是继续黑屏。
    public var onUnavailable: ((String) -> Void)?
    public private(set) var lastError: String?
    /// 幕帘期间是否隐藏鼠标指针（设置里可关）。
    public var hidesCursor = true
    /// 输出层纯色。gamma 表没有空间信息，不能承载图片或文字。
    public var backgroundColor: CurtainColor = .black
    private var cursorHiddenDisplayIDs: [CGDirectDisplayID] = []
    private let blackout = DisplayBlackout()
    private var refreshTimer: Timer?
    private var targetDisplayIDs: Set<CGDirectDisplayID> = []
    public var displayIDs: Set<CGDirectDisplayID> { targetDisplayIDs }

    private var demotedForAuth = false

    public init() {}

    public static func supportsOutputBlackout(_ displayID: CGDirectDisplayID) -> Bool {
        DisplayBlackout.supportsBlackout(displayID)
    }

    @discardableResult
    public func raise(displayIDs: [CGDirectDisplayID]? = nil) -> Bool {
        guard !isUp else { return true }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else {
            lastError = "没有可用的显示器"
            return false
        }
        demotedForAuth = false
        lastError = nil

        let targets = Set(displayIDs ?? screens.map(\.displayID))
        guard !targets.isEmpty else {
            lastError = "没有需要输出层遮挡的显示器"
            return false
        }
        targetDisplayIDs = targets
        guard blackout.apply(to: Array(targets), color: backgroundColor),
              blackout.blackedDisplayIDs == targets else {
            let failed = targets.filter { !blackout.blackedDisplayIDs.contains($0) }
            // 不能把 sharingType=.none 的黑窗当成默认 fallback：它只覆盖尊重窗口
            // 共享排除的采集链路，不能覆盖硬件采集/私有采集路径。宁可失败并撤幕。
            blackout.restoreAll()
            lastError = "显示器 \(failed.map(String.init).joined(separator: ",")) 不支持输出层黑幕"
            return false
        }
        isUp = true
        applyCursorVisibility()
        startRefreshTimer()
        return true
    }

    public func lower() {
        stopRefreshTimer()
        closeAuthWindows()
        blackout.restoreAll()
        isUp = false
        demotedForAuth = false
        targetDisplayIDs.removeAll()
        for displayID in cursorHiddenDisplayIDs {
            CGDisplayShowCursor(displayID)
        }
        cursorHiddenDisplayIDs.removeAll()
    }

    @discardableResult
    public func demoteForAuth() -> Bool {
        guard isUp, !demotedForAuth else { return isUp }
        demotedForAuth = true

        // gamma 只能整屏恢复；恢复后用普通层级黑窗继续盖住所有应用。
        blackout.restoreAll()
        let screens = ScreenInventory.current().filter {
            targetDisplayIDs.contains($0.displayID)
        }
        guard !screens.isEmpty else {
            failClosed("认证前没有可用的输出层幕帘显示器")
            return false
        }
        buildAuthWindows(for: screens, level: .normal, ignoresMouseEvents: false)
        return true
    }

    public func restoreLevel() {
        guard isUp, demotedForAuth else { return }
        demotedForAuth = false

        closeAuthWindows()
        let displayIDs = Array(targetDisplayIDs)
        if !blackout.apply(to: displayIDs, color: backgroundColor)
            || blackout.blackedDisplayIDs != targetDisplayIDs {
            blackout.restoreAll()
            failClosed("认证结束后无法恢复输出层黑幕")
            return
        }
        applyCursorVisibility()
    }

    /// gamma 会在唤醒/显示器重配后被系统重置，定时补涂。
    public func refreshBlackout() {
        guard isUp, !demotedForAuth else { return }
        if blackout.refresh() { return }
        // 立即再试一次，仍失败就撤幕；屏幕已经可能露出来了，不能继续赌。
        if blackout.refresh() { return }
        failClosed("显示器无法维持输出层黑幕")
    }

    /// 单屏角色变化时只更新 gamma 目标集合；不再纳入集合的屏幕恢复原色表。
    @discardableResult
    public func reconfigure(displayIDs: [CGDirectDisplayID]) -> Bool {
        guard isUp else { return raise(displayIDs: displayIDs) }
        targetDisplayIDs = Set(displayIDs)
        if demotedForAuth {
            closeAuthWindows()
            let targets = ScreenInventory.current().filter {
                targetDisplayIDs.contains($0.displayID)
            }
            guard !targets.isEmpty else {
                failClosed("认证期间输出层幕帘显示器已全部断开")
                return false
            }
            buildAuthWindows(for: targets, level: .normal, ignoresMouseEvents: false)
            return true
        }
        guard !targetDisplayIDs.isEmpty else {
            lower()
            return true
        }
        guard blackout.apply(to: Array(targetDisplayIDs), color: backgroundColor),
              blackout.blackedDisplayIDs == targetDisplayIDs else {
            blackout.restoreAll()
            failClosed("显示器角色变化后无法恢复输出层黑幕")
            return false
        }
        applyCursorVisibility()
        return true
    }

    /// 显示器热插拔/分辨率变化时重建，避免只盖住其中一块。
    @discardableResult
    public func rebuildIfNeeded() -> Bool {
        guard isUp else { return true }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else {
            failClosed("所有显示器已断开")
            return false
        }

        let currentIDs = Set(screens.map(\.displayID))
        for displayID in authWindows.keys where !currentIDs.contains(displayID) {
            if let window = authWindows.removeValue(forKey: displayID) {
                window.orderOut(nil)
                window.close()
            }
        }

        if demotedForAuth {
            let targets = screens.filter {
                targetDisplayIDs.contains($0.displayID)
            }
            guard !targets.isEmpty else {
                failClosed("输出层幕帘显示器已全部断开")
                return false
            }
            for screen in targets {
                if let window = authWindows[screen.displayID] {
                    if window.frame != screen.frame {
                        window.setFrame(screen.frame, display: true)
                    }
                    window.level = .normal
                    window.ignoresMouseEvents = false
                } else {
                    authWindows[screen.displayID] = makeWindow(
                        for: screen,
                        level: .normal,
                        ignoresMouseEvents: false
                    )
                }
            }
        } else {
            let displayIDs = targetDisplayIDs.isEmpty
                ? screens.map(\.displayID)
                : Array(targetDisplayIDs)
            if !blackout.apply(to: displayIDs, color: backgroundColor)
                || blackout.blackedDisplayIDs.count != displayIDs.count {
                blackout.restoreAll()
                failClosed("显示器变化后无法恢复输出层黑幕")
                return false
            }
        }

        applyCursorVisibility()
        return true
    }

    /// 幕帘升起期间切换背景色。直接重写 gamma，不清空原表，所以不会短暂露出桌面。
    public func setBackgroundColor(_ color: CurtainColor) {
        backgroundColor = color
        guard isUp, !demotedForAuth else { return }
        let displayIDs = targetDisplayIDs.isEmpty
            ? ScreenInventory.current().map(\.displayID)
            : Array(targetDisplayIDs)
        guard !displayIDs.isEmpty,
              blackout.apply(to: displayIDs, color: color),
              blackout.blackedDisplayIDs.count == displayIDs.count else {
            blackout.restoreAll()
            failClosed("无法应用新的幕帘背景色")
            return
        }
    }

    /// 设置里的「隐藏指针」变化后立即生效，不需要重新升幕帘。
    public func applyCursorVisibility() {
        guard isUp else { return }
        if hidesCursor {
            let visibleCursorIDs = Set(cursorHiddenDisplayIDs)
            for screen in ScreenInventory.current() where !visibleCursorIDs.contains(screen.displayID) {
                CGDisplayHideCursor(screen.displayID)
                cursorHiddenDisplayIDs.append(screen.displayID)
            }
        } else {
            for displayID in cursorHiddenDisplayIDs {
                CGDisplayShowCursor(displayID)
            }
            cursorHiddenDisplayIDs.removeAll()
        }
    }

    private func buildAuthWindows(
        for screens: [ScreenSnapshot],
        level: NSWindow.Level,
        ignoresMouseEvents: Bool
    ) {
        closeAuthWindows()
        for screen in screens {
            authWindows[screen.displayID] = makeWindow(
                for: screen,
                level: level,
                ignoresMouseEvents: ignoresMouseEvents
            )
        }
    }

    private func closeAuthWindows() {
        for window in authWindows.values {
            window.orderOut(nil)
            window.close()
        }
        authWindows.removeAll()
    }

    private func failClosed(_ message: String) {
        lastError = message
        lower()
        onUnavailable?(message)
    }

    private func makeWindow(
        for screen: ScreenSnapshot,
        level: NSWindow.Level,
        ignoresMouseEvents: Bool
    ) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // 默认 true：close() 会额外 release 一次，和 ARC 的强引用叠加就是 over-release，
        // 表现为"向已释放对象发消息"的崩溃（本次闪退的根因）。
        window.isReleasedWhenClosed = false
        window.level = level
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = ignoresMouseEvents
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        // Night Shift / True Tone / ColorSync 都可能重写 gamma；1 秒的窗口足以
        // 让屏幕短暂露出桌面。4 Hz 的成本很低，先保住可见性边界。
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshBlackout()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
