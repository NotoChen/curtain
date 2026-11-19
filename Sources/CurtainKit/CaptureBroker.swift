import AppKit
import CryptoKit
import Foundation
import ScreenCaptureKit

public struct CaptureResult {
    public let url: URL
    public let width: Int
    public let height: Int
    public let sha256: String
}

public struct CaptureOptions {
    public var cursor: Bool
    /// 区域截图，单位是点，相对该屏左上角
    public var region: CGRect?
    public var fps: Int
    /// 0 表示交给编码器自动决定
    public var bitrate: Int

    public init(cursor: Bool = false, region: CGRect? = nil, fps: Int = 30, bitrate: Int = 0) {
        self.cursor = cursor
        self.region = region
        self.fps = fps
        self.bitrate = bitrate
    }
}

public enum CaptureError: Error, CustomStringConvertible {
    case noDisplay
    case encodeFailed
    case timedOut
    case underlying(String)

    public var description: String {
        switch self {
        case .noDisplay: return "没有可用的显示器"
        case .encodeFailed: return "PNG 编码失败"
        case .timedOut: return "采集超时"
        case .underlying(let m): return m
        }
    }
}

private final class AsyncResultBox<T> {
    var value: Result<T, Error>?
}

/// 采集：按屏抓取完整桌面，并用 `excludingApplications` 把 Curtain 自己排除掉。
/// 认证窗口另外设置了 sharingType = .none；默认幕帘走 gamma，不依赖窗口排除。
public final class CaptureBroker {
    public init() {}

    public func displayCount() -> Int {
        (try? sync {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.displays.count
        }) ?? 0
    }

    public func displayIDs() -> [CGDirectDisplayID] {
        resolveOnMain { ScreenInventory.current().map(\.displayID) }
    }

    public func screenshot(to outURL: URL, displayIndex: Int = 0, options: CaptureOptions = CaptureOptions()) throws -> CaptureResult {
        guard let screen = resolveOnMain({ ScreenInventory.screen(at: displayIndex) }) else {
            throw CaptureError.noDisplay
        }
        return try screenshot(to: outURL, screen: screen, options: options)
    }

    public func screenshot(to outURL: URL, displayID: CGDirectDisplayID,
                           options: CaptureOptions = CaptureOptions()) throws -> CaptureResult {
        guard let screen = resolveOnMain({ ScreenInventory.screen(for: displayID) }) else {
            throw CaptureError.noDisplay
        }
        return try screenshot(to: outURL, screen: screen, options: options)
    }

    /// 对每块屏各截一张：<base>-0.png、<base>-1.png …
    public func screenshotAllDisplays(to directory: URL, baseName: String, options: CaptureOptions = CaptureOptions()) throws -> [CaptureResult] {
        let screens = resolveOnMain { ScreenInventory.current() }
        guard !screens.isEmpty else { throw CaptureError.noDisplay }
        var results: [CaptureResult] = []
        for (index, screen) in screens.enumerated() {
            let url = directory.appendingPathComponent("\(baseName)-\(index).png")
            results.append(try screenshot(to: url, screen: screen, options: options))
        }
        return results
    }

    private func makeFilter(screen: ScreenSnapshot,
                            options: CaptureOptions) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.noDisplay
        }
        let own = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

        let cfg = SCStreamConfiguration()
        // SCK 的 width/height 按像素算，SCDisplay 给的常是点。几何信息在进入
        // async 任务前已经从主线程取好，避免后台线程再次同步主线程造成死锁。
        let scale = max(1, screen.scale)
        if let region = options.region {
            cfg.sourceRect = region
            cfg.width = max(1, Int(region.width * scale))
            cfg.height = max(1, Int(region.height * scale))
        } else {
            cfg.width = max(1, Int(screen.frame.width * scale))
            cfg.height = max(1, Int(screen.frame.height * scale))
        }
        cfg.showsCursor = options.cursor
        cfg.captureResolution = .best
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.fps)))
        cfg.queueDepth = 6
        return (filter, cfg)
    }

    public func startRecording(_ recorder: Recorder, to url: URL, displayIndex: Int = 0,
                               options: CaptureOptions = CaptureOptions()) throws {
        guard let screen = resolveOnMain({ ScreenInventory.screen(at: displayIndex) }) else {
            throw CaptureError.noDisplay
        }
        try startRecording(recorder, to: url, screen: screen, options: options)
    }

    public func startRecording(_ recorder: Recorder, to url: URL, displayID: CGDirectDisplayID,
                               options: CaptureOptions = CaptureOptions()) throws {
        guard let screen = resolveOnMain({ ScreenInventory.screen(for: displayID) }) else {
            throw CaptureError.noDisplay
        }
        try startRecording(recorder, to: url, screen: screen, options: options)
    }

    private func screenshot(to outURL: URL, screen: ScreenSnapshot,
                            options: CaptureOptions) throws -> CaptureResult {
        try sync { try await self.capture(to: outURL, screen: screen, options: options) }
    }

    private func startRecording(_ recorder: Recorder, to url: URL, screen: ScreenSnapshot,
                                options: CaptureOptions) throws {
        try sync {
            let (filter, cfg) = try await self.makeFilter(screen: screen, options: options)
            try recorder.start(filter: filter, configuration: cfg, to: url, bitrate: options.bitrate)
        }
    }

    private func capture(to outURL: URL, screen: ScreenSnapshot,
                         options: CaptureOptions) async throws -> CaptureResult {
        let (filter, cfg) = try await makeFilter(screen: screen, options: options)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError.encodeFailed }
        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outURL)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outURL.path
        )
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CaptureResult(url: outURL, width: image.width, height: image.height, sha256: digest)
    }

    /// 读取 NSScreen 几何必须在主线程；这里只从调用线程同步一次，
    /// 不会在 `sync` 内部的 async 任务里再次切主线程。
    private func resolveOnMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread {
            return body()
        }
        return DispatchQueue.main.sync(execute: body)
    }

    /// 把 async 的 SCK 调用折成同步，供 socket 线程直接调用。
    private func sync<T>(_ body: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<T>()
        Task.detached {
            do { box.value = .success(try await body()) } catch { box.value = .failure(error) }
            sem.signal()
        }
        if sem.wait(timeout: .now() + 30) == .timedOut { throw CaptureError.timedOut }
        guard let result = box.value else { throw CaptureError.underlying("采集未返回结果") }
        return try result.get()
    }
}
