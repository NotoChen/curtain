import CryptoKit
import Foundation

/// 追加式 JSONL 审计，带哈希链：每条记录含上一条的 hash，
/// 任何一条被删/改都会在 `verify` 时暴露。
public final class AuditLog {
    private let url: URL
    private let queue = DispatchQueue(label: "curtain.audit")
    private var lastHash: String = ""
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(url: URL = Paths.auditURL) {
        self.url = url
        self.lastHash = AuditLog.tailHash(of: url)
    }

    public func write(_ event: String, _ details: [String: Any] = [:]) {
        let ts = formatter.string(from: Date())
        queue.async { [url] in
            var payload: [String: Any] = ["ts": ts, "event": event, "prev": self.lastHash]
            for (k, v) in details { payload[k] = v }
            guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
            let hash = AuditLog.sha256(body)
            payload["hash"] = hash
            guard let line = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
            var record = line
            record.append(0x0A)
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(record)
                try? fh.close()
            } else {
                try? record.write(to: url)
            }
            self.lastHash = hash
        }
    }

    public func tail(_ count: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(count).map(String.init)
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
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return VerifyResult(ok: true, count: 0, legacy: 0, brokenAtLine: nil, reason: "没有审计文件")
        }
        var previous = ""
        var count = 0
        var legacy = 0
        for (index, line) in text.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return VerifyResult(ok: false, count: count, legacy: legacy, brokenAtLine: index + 1, reason: "第 \(index + 1) 行不是合法 JSON")
            }
            let storedHash = payload["hash"] as? String ?? ""
            // 旧格式（引入哈希链之前）没有 hash 字段：跳过，从下一条开始重新起链。
            if storedHash.isEmpty {
                legacy += 1
                previous = ""
                continue
            }
            payload.removeValue(forKey: "hash")

            let prev = payload["prev"] as? String ?? ""
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
        return VerifyResult(ok: true, count: count, legacy: legacy, brokenAtLine: nil, reason: nil)
    }

    // MARK: - 工具

    private static func tailHash(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let last = text.split(separator: "\n").last,
              let data = last.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return payload["hash"] as? String ?? ""
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
