import Foundation

/// 运行配置。只保留用户真正会调的东西；截图目录、码率这些属于命令行参数，不在这里。
/// 新增字段全部带默认值，老配置文件可以直接升级（未知字段自动忽略）。
public struct CurtainConfig: Codable {
    /// 长按 Esc 多少秒后弹出 Touch ID。
    public var holdToAuthSeconds: Double
    /// 开发兜底：入幕后多少秒自动撤幕，0 表示关闭（默认关闭）。
    public var safetyTimeoutSeconds: Double
    /// 幕帘期间是否隐藏鼠标指针。
    public var hideCursorDuringCurtain: Bool

    public init(holdToAuthSeconds: Double = 2.0,
                safetyTimeoutSeconds: Double = 0,
                hideCursorDuringCurtain: Bool = true) {
        self.holdToAuthSeconds = holdToAuthSeconds
        self.safetyTimeoutSeconds = safetyTimeoutSeconds
        self.hideCursorDuringCurtain = hideCursorDuringCurtain
    }

    private enum CodingKeys: String, CodingKey {
        case holdToAuthSeconds, safetyTimeoutSeconds, hideCursorDuringCurtain
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holdToAuthSeconds = try c.decodeIfPresent(Double.self, forKey: .holdToAuthSeconds) ?? 2.0
        safetyTimeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .safetyTimeoutSeconds) ?? 0
        hideCursorDuringCurtain = try c.decodeIfPresent(Bool.self, forKey: .hideCursorDuringCurtain) ?? true
    }

    public static let `default` = CurtainConfig()

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
