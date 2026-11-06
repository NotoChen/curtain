import Foundation

/// 运行配置。首次启动会写一份默认配置到 ~/Library/Application Support/Curtain/config.json。
public struct CurtainConfig: Codable {
    /// 允许在幕帘期间注入输入的执行体。"/" 开头按可执行文件路径前缀匹配，否则按 bundle id 精确匹配。
    public var allowlist: [String]
    /// 长按 Esc 多少秒后弹出 Touch ID。
    public var holdToAuthSeconds: Double
    /// 安全兜底自动撤幕秒数，0 表示关闭（默认关闭）。
    public var safetyTimeoutSeconds: Double

    public init(allowlist: [String], holdToAuthSeconds: Double, safetyTimeoutSeconds: Double) {
        self.allowlist = allowlist
        self.holdToAuthSeconds = holdToAuthSeconds
        self.safetyTimeoutSeconds = safetyTimeoutSeconds
    }

    public static let `default` = CurtainConfig(
        allowlist: [
            "/Applications/Cua Driver.app",
            "com.nousresearch.cua-driver",
            "com.apple.Terminal",
            "/usr/bin/osascript",
        ],
        holdToAuthSeconds: 2.0,
        safetyTimeoutSeconds: 0
    )

    public static func load() -> CurtainConfig {
        guard let data = try? Data(contentsOf: Paths.configURL),
              let cfg = try? JSONDecoder().decode(CurtainConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public func save() {
        Paths.ensureSupportDir()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Paths.configURL)
        }
    }
}
