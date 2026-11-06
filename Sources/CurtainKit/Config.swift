import Foundation

/// 运行配置。首次启动会写一份默认配置到 ~/Library/Application Support/Curtain/config.json。
/// 新增字段全部带默认值，老配置文件可以直接升级。
public struct CurtainConfig: Codable {
    /// 允许在幕帘期间注入输入的执行体。"/" 开头按可执行文件路径前缀匹配，否则按 bundle id 精确匹配。
    public var allowlist: [String]
    /// 长按 Esc 多少秒后弹出 Touch ID。
    public var holdToAuthSeconds: Double
    /// 安全兜底自动撤幕秒数，0 表示关闭（默认关闭）。
    public var safetyTimeoutSeconds: Double
    /// 幕帘期间是否隐藏鼠标指针。
    public var hideCursorDuringCurtain: Bool
    /// 截图默认输出目录，空字符串表示 Application Support 目录。
    public var captureDirectory: String
    /// 截图默认是否包含鼠标指针。
    public var captureCursor: Bool
    /// 录屏默认帧率。
    public var recordingFPS: Int
    /// 录屏默认码率，0 表示交给编码器。
    public var recordingBitrate: Int

    public init(allowlist: [String],
                holdToAuthSeconds: Double,
                safetyTimeoutSeconds: Double,
                hideCursorDuringCurtain: Bool = true,
                captureDirectory: String = "",
                captureCursor: Bool = false,
                recordingFPS: Int = 30,
                recordingBitrate: Int = 0) {
        self.allowlist = allowlist
        self.holdToAuthSeconds = holdToAuthSeconds
        self.safetyTimeoutSeconds = safetyTimeoutSeconds
        self.hideCursorDuringCurtain = hideCursorDuringCurtain
        self.captureDirectory = captureDirectory
        self.captureCursor = captureCursor
        self.recordingFPS = recordingFPS
        self.recordingBitrate = recordingBitrate
    }

    private enum CodingKeys: String, CodingKey {
        case allowlist, holdToAuthSeconds, safetyTimeoutSeconds
        case hideCursorDuringCurtain, captureDirectory, captureCursor, recordingFPS, recordingBitrate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? CurtainConfig.default.allowlist
        holdToAuthSeconds = try c.decodeIfPresent(Double.self, forKey: .holdToAuthSeconds) ?? 2.0
        safetyTimeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .safetyTimeoutSeconds) ?? 0
        hideCursorDuringCurtain = try c.decodeIfPresent(Bool.self, forKey: .hideCursorDuringCurtain) ?? true
        captureDirectory = try c.decodeIfPresent(String.self, forKey: .captureDirectory) ?? ""
        captureCursor = try c.decodeIfPresent(Bool.self, forKey: .captureCursor) ?? false
        recordingFPS = try c.decodeIfPresent(Int.self, forKey: .recordingFPS) ?? 30
        recordingBitrate = try c.decodeIfPresent(Int.self, forKey: .recordingBitrate) ?? 0
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
