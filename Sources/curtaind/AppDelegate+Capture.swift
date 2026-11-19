import AppKit
import CurtainKit

extension AppDelegate {
    func capture(_ request: ControlRequest, peer: ProcessPeer?) -> ControlResponse {
        let options = captureOptions(request)
        let caller = requestCaller(request, peer: peer)
        do {
            if request.allDisplays == true {
                let fallback = defaultOutputURL(extension: "png").deletingLastPathComponent()
                let dir = request.out.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? fallback
                let base = request.out.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                    ?? "shot-\(Int(Date().timeIntervalSince1970))"
                let results = try broker.screenshotAllDisplays(to: dir, baseName: base, options: options)
                audit.write("capture_all", [
                    "count": results.count,
                    "dir": dir.path,
                    "cursor": options.cursor,
                ].merging(callerAudit(request, peer: peer)) { _, new in new })
                return ControlResponse(ok: true, message: "已保存 \(results.count) 张（每屏一张）", data: [
                    "count": "\(results.count)",
                    "dir": dir.path,
                    "paths": results.map { $0.url.path }.joined(separator: ","),
                    "caller": caller ?? "unknown",
                ])
            }

            let out = request.out ?? defaultOutputURL(extension: "png").path
            let result: CaptureResult
            if let displayID = request.displayID {
                result = try broker.screenshot(
                    to: URL(fileURLWithPath: out),
                    displayID: displayID,
                    options: options
                )
            } else {
                result = try broker.screenshot(
                    to: URL(fileURLWithPath: out),
                    displayIndex: request.display ?? 0,
                    options: options
                )
            }
            let curtainState = curtainStateString()
            audit.write("capture", [
                "path": result.url.path,
                "width": result.width,
                "height": result.height,
                "sha256": result.sha256,
                "cursor": options.cursor,
                "region": request.region ?? "",
                "curtain": curtainState,
            ].merging(callerAudit(request, peer: peer)) { _, new in new })
            return ControlResponse(ok: true, message: "已保存", data: [
                "path": result.url.path,
                "width": "\(result.width)",
                "height": "\(result.height)",
                "sha256": result.sha256,
                "caller": caller ?? "unknown",
            ])
        } catch {
            audit.write("capture_failed", ["error": "\(error)"])
            return .failure("截图失败：\(error)")
        }
    }

    func recordStart(_ request: ControlRequest, peer: ProcessPeer?) -> ControlResponse {
        guard !recorder.isRecording else { return .failure("已经在录制") }
        let out = request.out ?? defaultOutputURL(extension: "mp4").path
        let options = captureOptions(request)
        let curtainState = curtainStateString()
        let caller = requestCaller(request, peer: peer)
        do {
            if let displayID = request.displayID {
                try broker.startRecording(
                    recorder,
                    to: URL(fileURLWithPath: out),
                    displayID: displayID,
                    options: options
                )
            } else {
                try broker.startRecording(
                    recorder,
                    to: URL(fileURLWithPath: out),
                    displayIndex: request.display ?? 0,
                    options: options
                )
            }
            audit.write("record_start", [
                "path": out,
                "fps": options.fps,
                "bitrate": options.bitrate,
                "curtain": curtainState,
            ].merging(callerAudit(request, peer: peer)) { _, new in new })
            activeRecordingStartedAt = Date()
            activeRecordingClient = caller
            updateStatusItem()
            return ControlResponse(ok: true, message: "开始录制", data: [
                "path": out,
                "fps": "\(options.fps)",
                "bitrate": "\(options.bitrate)",
                "caller": caller ?? "unknown",
            ])
        } catch {
            updateStatusItem()
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("录制启动失败：\(error)")
        }
    }

    func recordStop() -> ControlResponse {
        do {
            let frames = recorder.snapshot().framesAppended
            let url = try recorder.stop()
            let client = activeRecordingClient
            activeRecordingStartedAt = nil
            activeRecordingClient = nil
            updateStatusItem()
            audit.write("record_stop", [
                "path": url.path,
                "frames": frames,
                "client": client ?? "unspecified",
            ])
            return ControlResponse(ok: true, message: "录制结束", data: ["path": url.path, "frames": "\(frames)"])
        } catch {
            updateStatusItem()
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("结束录制失败：\(error)")
        }
    }

    private func captureOptions(_ request: ControlRequest) -> CaptureOptions {
        var region: CGRect?
        if let raw = request.region {
            let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                region = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        return CaptureOptions(
            cursor: request.cursor ?? false,
            region: region,
            fps: max(1, min(request.fps ?? 30, 60)),
            bitrate: max(0, request.bitrate ?? 0)
        )
    }

    func requestCaller(_ request: ControlRequest, peer: ProcessPeer?) -> String? {
        normalizedClient(
            CallerAttribution.displayName(peer: peer, label: request.client)
        )
    }

    private func callerAudit(_ request: ControlRequest, peer: ProcessPeer?) -> [String: Any] {
        var details: [String: Any] = [
            "client": request.client ?? "unspecified",
        ]
        if let peer {
            details["caller"] = peer.displayName
            details["caller_process"] = peer.direct.name
            details["caller_parent"] = peer.principal.name
            details["caller_environment"] = peer.environmentHint ?? ""
            details["caller_pid"] = peer.direct.pid
            details["caller_path"] = peer.direct.executablePath
            details["caller_parent_pid"] = peer.principal.pid
            details["caller_parent_path"] = peer.principal.executablePath
            details["caller_chain"] = peer.chainText
            details["caller_pids"] = peer.pidChain
        } else {
            details["caller"] = "unknown"
        }
        return details
    }

    private func normalizedClient(_ client: String?) -> String? {
        let trimmed = client?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(48))
    }

    /// 默认输出位置：Application Support（截图目录属于调用方参数，用户不需要配）。
    private func defaultOutputURL(extension ext: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        return Paths.supportDir.appendingPathComponent("curtain-\(stamp).\(ext)")
    }
}
