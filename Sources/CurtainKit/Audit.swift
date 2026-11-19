import CryptoKit
import Darwin
import Foundation

/// 追加式 JSONL 审计，带哈希链。
/// 它用于发现中途改写、删除和损坏，不防同用户重写整份文件或截断末尾。
public final class AuditLog {
    private let url: URL
    private let queue = DispatchQueue(label: "curtain.audit")
    private var lastHash: String = ""
    private var writeFailures = 0
    private var lastWriteError: String?
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public struct Status {
        public let writeFailures: Int
        public let lastWriteError: String?
    }

    public init(url: URL = Paths.auditURL) {
        self.url = url
        self.lastHash = AuditLog.tailHash(of: url)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    public func write(_ event: String, _ details: [String: Any] = [:]) {
        queue.async { [url] in
            let timestamp = self.formatter.string(from: Date())
            var payload: [String: Any] = [
                "ts": timestamp,
                "event": event,
                "prev": self.lastHash,
            ]
            for (key, value) in details {
                payload[key] = value
            }
            guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                self.recordFailure("无法序列化审计事件 \(event)")
                return
            }
            let hash = AuditLog.sha256(body)
            payload["hash"] = hash
            guard var record = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                self.recordFailure("无法序列化带 hash 的审计事件 \(event)")
                return
            }
            record.append(0x0A)

            do {
                try AuditLog.append(record, to: url)
                self.lastHash = hash
            } catch {
                self.recordFailure("\(error)")
            }
        }
    }

    public func tail(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        return queue.sync {
            guard let text = try? AuditLog.readText(at: url) else { return [] }
            return text.split(separator: "\n").suffix(min(count, 10_000)).map(String.init)
        }
    }

    /// 等待当前队列中的审计写入完成。
    public func flush() {
        queue.sync {}
    }

    public func status() -> Status {
        queue.sync {
            Status(writeFailures: writeFailures, lastWriteError: lastWriteError)
        }
    }

    private func recordFailure(_ message: String) {
        writeFailures += 1
        lastWriteError = message
    }

    // MARK: - 链校验

    public struct VerifyResult {
        public let ok: Bool
        public let count: Int
        public let legacy: Int
        public let brokenAtLine: Int?
        public let reason: String?
    }

    public static func verify(_ url: URL = Paths.auditURL) -> VerifyResult {
        let text: String
        do {
            guard let read = try readText(at: url) else {
                return VerifyResult(ok: true, count: 0, legacy: 0, brokenAtLine: nil, reason: "没有审计文件")
            }
            text = read
        } catch {
            return VerifyResult(ok: false, count: 0, legacy: 0, brokenAtLine: nil, reason: "无法读取审计文件：\(error)")
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }

        var previous = ""
        var count = 0
        var legacy = 0
        var hashedSeen = false
        var legacyAfterChainStart: Int?
        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "空行")
            }
            guard let data = line.data(using: .utf8),
                  var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "第 \(index + 1) 行不是合法 JSON")
            }
            let storedHash = payload["hash"] as? String ?? ""
            if storedHash.isEmpty {
                if hashedSeen, legacyAfterChainStart == nil {
                    legacyAfterChainStart = index + 1
                }
                legacy += 1
                previous = ""
                continue
            }
            payload.removeValue(forKey: "hash")

            let prev = payload["prev"] as? String ?? ""
            if legacyAfterChainStart != nil {
                guard prev.isEmpty else {
                    return VerifyResult(
                        ok: false,
                        count: count,
                        legacy: legacy,
                        brokenAtLine: index + 1,
                        reason: "旧格式记录之后的新链 prev 不为空"
                    )
                }
                legacyAfterChainStart = nil
            }
            hashedSeen = true
            if prev != previous {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "prev 与上一条 hash 不一致")
            }
            guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "无法重新序列化")
            }
            if sha256(body) != storedHash {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "hash 不匹配（内容被改过）")
            }
            previous = storedHash
            count += 1
        }
        if let legacyStart = legacyAfterChainStart {
            return VerifyResult(
                ok: false,
                count: count,
                legacy: legacy,
                brokenAtLine: legacyStart,
                reason: "哈希链末尾存在无 hash 记录"
            )
        }
        return VerifyResult(ok: true, count: count, legacy: legacy, brokenAtLine: nil, reason: nil)
    }

    // MARK: - 文件

    private static func append(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else {
            throw posixError("open")
        }
        defer { close(fd) }
        _ = fchmod(fd, 0o600)
        guard flock(fd, LOCK_EX) == 0 else {
            throw posixError("flock")
        }
        defer { _ = flock(fd, LOCK_UN) }

        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError("write")
                }
                guard written > 0 else {
                    throw NSError(
                        domain: "CurtainAudit",
                        code: Int(EIO),
                        userInfo: [NSLocalizedDescriptionKey: "审计写入返回 0"]
                    )
                }
                offset += written
            }
        }
        guard fsync(fd) == 0 else {
            throw posixError("fsync")
        }
    }

    private static func readText(at url: URL) throws -> String? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw posixError("open")
        }
        defer { close(fd) }
        guard flock(fd, LOCK_SH) == 0 else {
            throw posixError("flock")
        }
        defer { _ = flock(fd, LOCK_UN) }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "CurtainAudit",
                code: Int(EILSEQ),
                userInfo: [NSLocalizedDescriptionKey: "审计文件不是 UTF-8"]
            )
        }
        return text
    }

    private static func tailHash(of url: URL) -> String {
        guard let text = try? readText(at: url),
              let last = text.split(separator: "\n").last,
              let data = last.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        return payload["hash"] as? String ?? ""
    }

    private static func posixError(_ operation: String) -> NSError {
        let code = errno
        return NSError(
            domain: "CurtainAudit",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) 失败：\(String(cString: strerror(code)))"]
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
