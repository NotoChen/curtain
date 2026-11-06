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

/// 采集：按屏抓取完整桌面，并用 `excludingApplications` 把幕帘自己排除掉。
/// 幕帘窗口本身设了 sharingType = .none，这里是第二道保险。
public final class CaptureBroker {
    public init() {}

    public func displayCount() -> Int {
        (try? sync {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.displays.count
        }) ?? 0
    }

    public func screenshot(to outURL: URL, displayIndex: Int = 0) throws -> CaptureResult {
        try sync { try await self.capture(to: outURL, displayIndex: displayIndex) }
    }

    public func makeFilter(displayIndex: Int) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard displayIndex >= 0, displayIndex < content.displays.count else { throw CaptureError.noDisplay }
        let display = content.displays[displayIndex]
        let own = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = display.width
        cfg.height = display.height
        cfg.showsCursor = false
        cfg.captureResolution = .best
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.queueDepth = 6
        return (filter, cfg)
    }

    public func startRecording(_ recorder: Recorder, to url: URL, displayIndex: Int = 0) throws {
        try sync {
            let (filter, cfg) = try await self.makeFilter(displayIndex: displayIndex)
            try recorder.start(filter: filter, configuration: cfg, to: url)
        }
    }

    private func capture(to outURL: URL, displayIndex: Int) async throws -> CaptureResult {
        let (filter, cfg) = try await makeFilter(displayIndex: displayIndex)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError.encodeFailed }
        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CaptureResult(url: outURL, width: image.width, height: image.height, sha256: digest)
    }

    /// 把 async 的 SCK 调用折成同步，供 socket 线程直接调用。
    private func sync<T>(_ body: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task.detached {
            do { result = .success(try await body()) } catch { result = .failure(error) }
            sem.signal()
        }
        if sem.wait(timeout: .now() + 30) == .timedOut { throw CaptureError.timedOut }
        guard let result else { throw CaptureError.underlying("采集未返回结果") }
        return try result.get()
    }
}
