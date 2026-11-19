import AppKit
import Foundation

public struct PresentationPreviewConfiguration: Equatable {
    public var color: CurtainColor
    public var imagePath: String?
    public var clockStyle: PresentationClockStyle
    public var imageFocus: CGPoint
    public var imageZoom: CGFloat
    public var imageDim: CGFloat
    public var duration: TimeInterval

    public init(color: CurtainColor,
                imagePath: String?,
                clockStyle: PresentationClockStyle,
                imageFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                imageZoom: CGFloat = 1,
                imageDim: CGFloat = 0,
                duration: TimeInterval = 8) {
        self.color = color
        self.imagePath = imagePath
        self.clockStyle = clockStyle
        self.imageFocus = imageFocus
        self.imageZoom = imageZoom
        self.imageDim = imageDim
        self.duration = duration
    }
}

public enum PresentationPreviewError: Error, Equatable {
    case alreadyActive
    case noScreens
    case imageUnreadable
    case windowCreationFailed

    public var message: String {
        switch self {
        case .alreadyActive:
            return "已经有试看正在运行"
        case .noScreens:
            return "没有检测到可用的显示器"
        case .imageUnreadable:
            return "背景图无法读取"
        case .windowCreationFailed:
            return "无法创建全屏试看窗口"
        }
    }
}

/// 全屏试看只在所有显示器上渲染展示画布，不进入幕帘状态、不拦截键盘鼠标；
/// 到时自动关闭，避免把试看误当成真实保护。
public final class PresentationPreviewSession {
    private let overlay = PresentationOverlay()
    private var timer: Timer?
    private var remaining = 0
    private var completion: ((Result<Void, PresentationPreviewError>) -> Void)?

    public init() {
        overlay.hidesCursor = false
        overlay.blocksPointerEvents = true
    }

    deinit {
        timer?.invalidate()
        overlay.close()
    }

    public var isActive: Bool { overlay.isActive }
#if DEBUG
    public var allowsScreenCapture: Bool {
        get { overlay.allowsScreenCapture }
        set { overlay.allowsScreenCapture = newValue }
    }
#endif

    @discardableResult
    public func start(
        screens: [ScreenSnapshot],
        configuration: PresentationPreviewConfiguration,
        completion: @escaping (Result<Void, PresentationPreviewError>) -> Void
    ) -> PresentationPreviewError? {
        guard !overlay.isActive else { return .alreadyActive }
        guard !screens.isEmpty else { return .noScreens }
        if let path = configuration.imagePath,
           !path.isEmpty,
           !PresentationBackgroundLoader.isLoadable(path: path) {
            return .imageUnreadable
        }
        let duration = min(30, max(3, configuration.duration))
        remaining = Int(ceil(duration))
        self.completion = completion
        let status = previewStatus()
        guard overlay.show(
            screens: screens,
            color: configuration.color,
            imagePath: configuration.imagePath,
            clockStyle: configuration.clockStyle,
            imageFocus: configuration.imageFocus,
            imageZoom: configuration.imageZoom,
            imageDim: configuration.imageDim,
            status: status
        ) else {
            self.completion = nil
            return .windowCreationFailed
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return nil
    }

    public func stop(notify: Bool = true) {
        timer?.invalidate()
        timer = nil
        overlay.close()
        let completion = self.completion
        self.completion = nil
        if notify {
            completion?(.success(()))
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            stop()
            return
        }
        overlay.update(status: previewStatus())
    }

    private func previewStatus() -> PresentationStatus {
        var status = PresentationClockFormatter.status(
            at: Date(),
            startedAt: nil
        )
        status.elapsedText = "试看 · \(remaining) 秒后自动结束"
        return status
    }
}
