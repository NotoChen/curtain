import AppKit
import Foundation

/// 可选的「展示模式」：用窗口显示背景图和日期、时间、星期、农历。
///
/// 这条路径和默认 gamma 幕帘的保证不同：它依赖窗口共享排除，只承诺常规
/// ScreenCaptureKit 截图/录屏看不到；硬件采集、私有采集 API 不在保证范围内。
/// 默认关闭，开启后必须在设置里明确说明这个取舍。
public final class PresentationOverlay {
    private static let overlayLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    private struct ScreenWindow {
        var screen: ScreenSnapshot
        let window: NSWindow
        let canvas: PresentationCanvasView
    }

    private var windows: [ScreenWindow] = []
    private var cursorHiddenDisplayIDs: [CGDirectDisplayID] = []
    private var backgroundImage: CGImage?
    public var backgroundColor: CurtainColor = .black
    public var imagePath: String?
    public var clockStyle: PresentationClockStyle = .digital
    public var imageFocus = CGPoint(x: 0.5, y: 0.5)
    public var imageZoom: CGFloat = 1
    public var imageDim: CGFloat = 0
    public var hidesCursor = true
    public var blocksPointerEvents = false
#if DEBUG
    public var allowsScreenCapture = false
#endif
    private var lastStatus: PresentationStatus?

    public init() {}

    public var isActive: Bool { !windows.isEmpty }
    public var displayIDs: Set<CGDirectDisplayID> {
        Set(windows.map(\.screen.displayID))
    }

    @discardableResult
    public func show(screens: [ScreenSnapshot],
                     color: CurtainColor,
                     imagePath: String?,
                     clockStyle: PresentationClockStyle,
                     imageFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                     imageZoom: CGFloat = 1,
                     imageDim: CGFloat = 0,
                     status: PresentationStatus?) -> Bool {
        close()
        backgroundColor = color
        self.imagePath = imagePath
        self.clockStyle = clockStyle
        self.imageFocus = imageFocus
        self.imageZoom = imageZoom
        self.imageDim = imageDim
        lastStatus = status
        guard !screens.isEmpty else { return false }

        if let imagePath, !imagePath.isEmpty {
            let target = PresentationBackgroundLoader.recommendedPixelSize(
                for: screens
            )
            guard let image = PresentationBackgroundLoader.load(
                path: imagePath,
                maxPixelSize: target
            ) else {
                return false
            }
            backgroundImage = image
        } else {
            backgroundImage = nil
        }

        for screen in screens {
            let window = makeWindow(for: screen)
            windows.append(window)
        }
        applyCursorVisibility()
        update(status: status)
        return true
    }

    public func applyCursorVisibility() {
        guard isActive else { return }
        if hidesCursor {
            let hidden = Set(cursorHiddenDisplayIDs)
            for screen in ScreenInventory.current()
                where !hidden.contains(screen.displayID) {
                CGDisplayHideCursor(screen.displayID)
                cursorHiddenDisplayIDs.append(screen.displayID)
            }
        } else {
            restoreCursor()
        }
    }

    public func update(status: PresentationStatus?) {
        lastStatus = status
        guard let status else { return }
        for item in windows {
            item.canvas.update(status: status)
        }
    }

    public func setColor(_ color: CurtainColor) {
        backgroundColor = color
        for item in windows {
            item.window.backgroundColor = presentationNSColor(color)
            item.canvas.setColor(color)
        }
    }

    public func setImagePath(_ path: String?) {
        imagePath = path
        let screens = windows.map(\.screen)
        if let path, !path.isEmpty {
            backgroundImage = PresentationBackgroundLoader.load(
                path: path,
                maxPixelSize: PresentationBackgroundLoader.recommendedPixelSize(
                    for: screens
                )
            )
        } else {
            backgroundImage = nil
        }
        for item in windows {
            item.canvas.setBackgroundImage(
                backgroundImage,
                focus: imageFocus,
                zoom: imageZoom,
                dim: imageDim
            )
        }
    }

    public func setImagePresentation(focus: CGPoint,
                                     zoom: CGFloat,
                                     dim: CGFloat) {
        imageFocus = focus
        imageZoom = zoom
        imageDim = dim
        for item in windows {
            item.canvas.setBackgroundImage(
                backgroundImage,
                focus: focus,
                zoom: zoom,
                dim: dim
            )
        }
    }

    public func setClockStyle(_ style: PresentationClockStyle) {
        clockStyle = style
        for item in windows {
            item.canvas.setClockStyle(style)
        }
    }

    public func showReturnHint(_ text: String) {
        for item in windows {
            item.canvas.showReturnHint(text)
        }
    }

    public func hideReturnHint(animated: Bool = true) {
        for item in windows {
            item.canvas.hideReturnHint(animated: animated)
        }
    }

    /// 显示器热插拔/重排后重建窗口，沿用当前颜色、背景图、样式和状态。
    @discardableResult
    public func rebuild(screens: [ScreenSnapshot]) -> Bool {
        reconcile(screens: screens)
    }

    /// 只增减目标屏幕，不关闭仍然命中的窗口。混合多屏角色变化时，
    /// 调用方可以先给即将变成黑色的屏幕涂上 gamma，再移除对应展示窗口。
    @discardableResult
    public func reconcile(screens: [ScreenSnapshot]) -> Bool {
        guard !screens.isEmpty else {
            close()
            return false
        }
        if let path = imagePath, !path.isEmpty {
            backgroundImage = PresentationBackgroundLoader.load(
                path: path,
                maxPixelSize: PresentationBackgroundLoader.recommendedPixelSize(
                    for: screens
                )
            )
            guard backgroundImage != nil else { return false }
        }

        let targets = Set(screens.map(\.displayID))
        for displayID in Array(windows.map(\.screen.displayID))
            where !targets.contains(displayID) {
            guard let index = windows.firstIndex(
                where: { $0.screen.displayID == displayID }
            ) else { continue }
            let item = windows.remove(at: index)
            item.window.orderOut(nil)
            item.window.close()
        }

        for screen in screens {
            if let index = windows.firstIndex(
                where: { $0.screen.displayID == screen.displayID }
            ) {
                let item = windows[index]
                if item.screen.frame != screen.frame {
                    item.window.setFrame(screen.frame, display: true)
                    item.canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
                    windows[index].screen = screen
                }
                item.canvas.setBackgroundImage(
                    backgroundImage,
                    focus: imageFocus,
                    zoom: imageZoom,
                    dim: imageDim
                )
                item.window.orderFrontRegardless()
            } else {
                windows.append(makeWindow(for: screen))
            }
        }
        applyCursorVisibility()
        update(status: lastStatus)
        return true
    }

    /// 认证期间降低窗口层级，让系统 Touch ID 面板显形，但保留全屏遮挡，
    /// 避免展示模式把桌面露出来。与默认 gamma 模式的认证窗口策略一致。
    public func hideForAuth() {
        hideReturnHint(animated: false)
        for item in windows {
            item.window.level = .normal
            item.window.orderFrontRegardless()
        }
    }

    public func restoreAfterAuth() {
        for item in windows {
            item.window.level = Self.overlayLevel
            item.window.orderFrontRegardless()
        }
        update(status: lastStatus)
    }

    public func close() {
        hideReturnHint(animated: false)
        restoreCursor()
        for item in windows {
            item.window.orderOut(nil)
            item.window.close()
        }
        windows.removeAll()
        backgroundImage = nil
        lastStatus = nil
    }

    private func restoreCursor() {
        for displayID in cursorHiddenDisplayIDs {
            CGDisplayShowCursor(displayID)
        }
        cursorHiddenDisplayIDs.removeAll()
    }

    private func makeWindow(for screen: ScreenSnapshot) -> ScreenWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // 和默认幕帘一样盖住菜单栏、Dock 和通知；认证时只降低层级。
        window.level = Self.overlayLevel
        window.backgroundColor = presentationNSColor(backgroundColor)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = !blocksPointerEvents
#if DEBUG
        window.sharingType = allowsScreenCapture ? .readOnly : .none
#else
        window.sharingType = .none
#endif
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let canvas = PresentationCanvasView(
            color: backgroundColor,
            image: backgroundImage,
            focus: imageFocus,
            zoom: imageZoom,
            dim: imageDim,
            clockStyle: clockStyle,
            status: lastStatus
        )
        canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()

        return ScreenWindow(screen: screen, window: window, canvas: canvas)
    }
}
