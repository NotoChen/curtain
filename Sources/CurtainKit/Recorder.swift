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
        case .writerSetup(let m): return "无法创建录制文件：\(m)"
        case .notRecording: return "当前没有在录制"
        case .finishFailed(let m): return "录制收尾失败：\(m)"
        }
    }
}

/// 录屏：SCStream -> AVAssetWriter(H.264/MP4)，走 pixel buffer adaptor。
/// 用的是同一个排除幕帘的 filter，所以录出来的画面里也没有幕帘。
public final class Recorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPTS: CMTime?
    private let queue = DispatchQueue(label: "curtain.recorder")

    public private(set) var isRecording = false
    public private(set) var outputURL: URL?
    public private(set) var framesAppended = 0
    public private(set) var appendFailures = 0

    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration, to url: URL) throws {
        guard !isRecording else { throw RecorderError.writerSetup("已经在录制") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw RecorderError.writerSetup("\(error)")
        }

        let width = configuration.width
        let height = configuration.height
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writerSetup("writer 不接受视频输入") }
        writer.add(input)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.startWriting() else {
            throw RecorderError.writerSetup("startWriting 失败：\(writer.error.map { "\($0)" } ?? "unknown")")
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.stream = stream
        self.firstPTS = nil
        self.framesAppended = 0
        self.appendFailures = 0
        self.outputURL = url
        self.isRecording = true

        let sem = DispatchSemaphore(value: 0)
        var startError: Error?
        stream.startCapture { error in
            startError = error
            sem.signal()
        }
        if sem.wait(timeout: .now() + 10) == .timedOut {
            isRecording = false
            throw RecorderError.writerSetup("startCapture 超时")
        }
        if let startError {
            isRecording = false
            self.stream = nil
            self.writer = nil
            self.input = nil
            self.adaptor = nil
            throw RecorderError.writerSetup("\(startError)")
        }
    }

    public func stop() throws -> URL {
        guard isRecording, let writer, let input else { throw RecorderError.notRecording }

        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 5)

        input.markAsFinished()

        let sem2 = DispatchSemaphore(value: 0)
        writer.finishWriting { sem2.signal() }
        if sem2.wait(timeout: .now() + 30) == .timedOut {
            throw RecorderError.finishFailed("finishWriting 超时")
        }

        let url = writer.outputURL
        let frames = framesAppended
        let failures = appendFailures
        let status = writer.status
        let error = writer.error
        stream = nil
        self.writer = nil
        self.input = nil
        self.adaptor = nil
        isRecording = false

        guard status == .completed else {
            throw RecorderError.finishFailed("status=\(status.rawValue) frames=\(frames) failedAppends=\(failures) \(error.map { "\($0)" } ?? "")")
        }
        guard frames > 0 else {
            throw RecorderError.finishFailed("没有写入任何视频帧")
        }
        return url
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let writer, let adaptor else { return }
        guard writer.status == .writing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 幕帘/遮挡状态下的空帧不要写，否则时间轴会出现无意义的静止段。
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPTS == nil {
            firstPTS = pts
            writer.startSession(atSourceTime: pts)
        }
        if adaptor.append(pixelBuffer, withPresentationTime: pts) {
            framesAppended += 1
        } else {
            appendFailures += 1
        }
    }
}
