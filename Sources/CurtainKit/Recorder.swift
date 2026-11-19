import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public enum RecorderError: Error, CustomStringConvertible {
    case writerSetup(String)
    case notRecording
    case finishFailed(String)

    public var description: String {
        switch self {
        case .writerSetup(let message): return "无法创建录制文件：\(message)"
        case .notRecording: return "当前没有在录制"
        case .finishFailed(let message): return "录制收尾失败：\(message)"
        }
    }
}

private final class StartErrorBox {
    var value: Error?
}

/// 录屏：SCStream -> AVAssetWriter(H.264/MP4)，走 pixel buffer adaptor。
/// 所有 writer/stream 状态都由 stateLock 串行化，采集回调只从 sampleQueue 进入。
public final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    public struct Status {
        public let isRecording: Bool
        public let framesAppended: Int
        public let appendFailures: Int
        public let outputURL: URL?
        public let lastError: String?
    }

    private enum State {
        case idle
        case starting
        case recording
        case stopping
    }

    public var onUnexpectedStop: ((String) -> Void)?

    private let stateLock = NSLock()
    private let sampleQueue = DispatchQueue(label: "curtain.recorder.samples")
    private var state: State = .idle
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPTS: CMTime?
    private var frameCount = 0
    private var failureCount = 0
    private var currentOutputURL: URL?
    private var lastFailure: String?
    private var startupFailure: String?

    public var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state == .recording
    }

    public var outputURL: URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentOutputURL
    }

    public var framesAppended: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return frameCount
    }

    public var appendFailures: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return failureCount
    }

    public var lastError: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastFailure
    }

    public func snapshot() -> Status {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Status(
            isRecording: state == .recording,
            framesAppended: frameCount,
            appendFailures: failureCount,
            outputURL: currentOutputURL,
            lastError: lastFailure
        )
    }

    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration, to url: URL, bitrate: Int = 0) throws {
        stateLock.lock()
        guard state == .idle else {
            stateLock.unlock()
            throw RecorderError.writerSetup("已经在录制或正在切换录制状态")
        }
        state = .starting
        startupFailure = nil
        frameCount = 0
        failureCount = 0
        currentOutputURL = url
        lastFailure = nil
        stateLock.unlock()

        var createdWriter: AVAssetWriter?
        var createdStream: SCStream?
        var streamStarted = false

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw RecorderError.writerSetup("目标文件已存在：\(url.path)")
            }

            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            createdWriter = writer
            writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

            let width = configuration.width
            let height = configuration.height
            var settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
            if bitrate > 0 {
                settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitrate]
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw RecorderError.writerSetup("writer 不接受视频输入")
            }
            writer.add(input)

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: attributes
            )

            guard writer.startWriting() else {
                throw RecorderError.writerSetup(
                    "startWriting 失败：\(writer.error.map { "\($0)" } ?? "unknown")"
                )
            }
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            createdStream = stream
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

            stateLock.lock()
            self.stream = stream
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.firstPTS = nil
            stateLock.unlock()

            let semaphore = DispatchSemaphore(value: 0)
            let startError = StartErrorBox()
            stream.startCapture { error in
                startError.value = error
                semaphore.signal()
            }
            streamStarted = true

            if semaphore.wait(timeout: .now() + 10) == .timedOut {
                throw RecorderError.writerSetup("startCapture 超时")
            }
            if let error = startError.value {
                throw RecorderError.writerSetup("\(error)")
            }

            stateLock.lock()
            guard state == .starting, self.stream === stream, startupFailure == nil else {
                let reason = startupFailure ?? "stream 在启动期间停止"
                stateLock.unlock()
                throw RecorderError.writerSetup(reason)
            }
            state = .recording
            startupFailure = nil
            stateLock.unlock()
        } catch {
            abortStart(
                stream: createdStream,
                streamStarted: streamStarted,
                writer: createdWriter,
                outputURL: url
            )
            throw error
        }
    }

    public func stop() throws -> URL {
        stateLock.lock()
        guard state == .recording, let writer, let input else {
            stateLock.unlock()
            throw RecorderError.notRecording
        }
        state = .stopping
        let stream = self.stream
        stateLock.unlock()

        if let stream {
            let semaphore = DispatchSemaphore(value: 0)
            stream.stopCapture { _ in semaphore.signal() }
            _ = semaphore.wait(timeout: .now() + 5)
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        let finished = semaphore.wait(timeout: .now() + 30) == .success

        stateLock.lock()
        let frames = frameCount
        let failures = failureCount
        let status = writer.status
        let writerError = writer.error
        clearSessionLocked()
        if !finished {
            lastFailure = "finishWriting 超时"
        } else if status != .completed {
            lastFailure = "status=\(status.rawValue) frames=\(frames) failedAppends=\(failures) \(writerError.map { "\($0)" } ?? "")"
        }
        let failure = lastFailure
        stateLock.unlock()

        if !finished {
            writer.cancelWriting()
            throw RecorderError.finishFailed("finishWriting 超时")
        }
        guard status == .completed else {
            throw RecorderError.finishFailed(failure ?? "writer 状态异常")
        }
        guard frames > 0 else {
            stateLock.lock()
            lastFailure = "没有写入任何视频帧"
            stateLock.unlock()
            throw RecorderError.finishFailed("没有写入任何视频帧")
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: writer.outputURL.path
        )
        return writer.outputURL
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard state == .starting || state == .recording,
              let writer,
              writer.status == .writing,
              let adaptor else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: statusRaw),
           frameStatus != .complete {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPTS == nil {
            firstPTS = presentationTime
            writer.startSession(atSourceTime: presentationTime)
        }
        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameCount += 1
        } else {
            failureCount += 1
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        guard self.stream === stream else {
            stateLock.unlock()
            return
        }
        if state == .starting {
            let message = "录屏流在启动期间停止：\(error)"
            startupFailure = message
            lastFailure = message
            stateLock.unlock()
            return
        }
        guard state == .recording else {
            stateLock.unlock()
            return
        }
        let input = self.input
        let writer = self.writer
        let message = "录屏流意外停止：\(error)"
        lastFailure = message
        clearSessionLocked()
        stateLock.unlock()

        input?.markAsFinished()
        writer?.finishWriting {}
        DispatchQueue.main.async { [weak self] in
            self?.onUnexpectedStop?(message)
        }
    }

    private func abortStart(stream: SCStream?, streamStarted: Bool, writer: AVAssetWriter?, outputURL: URL) {
        stateLock.lock()
        if let stream, self.stream === stream {
            self.stream = nil
        }
        if let writer, self.writer === writer {
            self.writer = nil
            self.input = nil
            self.adaptor = nil
            self.firstPTS = nil
        }
        if state == .starting {
            state = .idle
            startupFailure = nil
        }
        currentOutputURL = nil
        stateLock.unlock()

        writer?.cancelWriting()
        if streamStarted, let stream {
            stream.stopCapture { _ in }
        }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func clearSessionLocked() {
        stream = nil
        writer = nil
        input = nil
        adaptor = nil
        firstPTS = nil
        state = .idle
    }
}
