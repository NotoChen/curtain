import Foundation

/// 追加式 JSONL 审计。任何一次入幕、撤幕、采集都会留一行，含图片 sha256。
public final class AuditLog {
    private let url: URL
    private let queue = DispatchQueue(label: "curtain.audit")
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(url: URL = Paths.auditURL) {
        self.url = url
    }

    public func write(_ event: String, _ details: [String: Any] = [:]) {
        let ts = formatter.string(from: Date())
        queue.async { [url] in
            var payload: [String: Any] = ["ts": ts, "event": event]
            for (k, v) in details { payload[k] = v }
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
            var line = data
            line.append(0x0A)
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(line)
                try? fh.close()
            } else {
                try? line.write(to: url)
            }
        }
    }

    public func tail(_ count: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(count).map(String.init)
    }
}
