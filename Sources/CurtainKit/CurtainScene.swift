import Foundation

/// 单个场景的完整配置。场景只影响本次会话，不修改全局展示模式。
public struct CurtainSceneProfile: Codable, Equatable {
    public var protectionMinutes: Int
    public var usesPresentation: Bool
    public var backgroundImagePath: String
    /// 空字符串表示跟随全局时钟样式。
    public var clockStyle: String
    public var message: String
    public var showsReturnTime: Bool
    /// nil 表示跟随全局主屏角色。
    public var mainDisplayRole: String?
    /// nil 表示跟随全局副屏角色。
    public var secondaryDisplayRole: String?

    private enum CodingKeys: String, CodingKey {
        case protectionMinutes, usesPresentation
        case backgroundImagePath, clockStyle, message, showsReturnTime
        case mainDisplayRole, secondaryDisplayRole
    }

    public init(protectionMinutes: Int,
                usesPresentation: Bool,
                backgroundImagePath: String = "",
                clockStyle: String = "",
                message: String = "",
                showsReturnTime: Bool = true,
                mainDisplayRole: String? = nil,
                secondaryDisplayRole: String? = nil) {
        self.protectionMinutes = min(1440, max(0, protectionMinutes))
        self.usesPresentation = usesPresentation
        self.backgroundImagePath = backgroundImagePath.count <= 4096
            ? backgroundImagePath
            : ""
        self.clockStyle = clockStyle.isEmpty
            ? ""
            : PresentationClockStyle.storedValue(clockStyle).rawValue
        self.message = String(message.prefix(160))
        self.showsReturnTime = showsReturnTime
        self.mainDisplayRole = Self.validRole(mainDisplayRole)
        self.secondaryDisplayRole = Self.validRole(secondaryDisplayRole)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            protectionMinutes: try c.decodeIfPresent(
                Int.self,
                forKey: .protectionMinutes
            ) ?? 0,
            usesPresentation: try c.decodeIfPresent(
                Bool.self,
                forKey: .usesPresentation
            ) ?? true,
            backgroundImagePath: try c.decodeIfPresent(
                String.self,
                forKey: .backgroundImagePath
            ) ?? "",
            clockStyle: try c.decodeIfPresent(
                String.self,
                forKey: .clockStyle
            ) ?? "",
            message: try c.decodeIfPresent(
                String.self,
                forKey: .message
            ) ?? "",
            showsReturnTime: try c.decodeIfPresent(
                Bool.self,
                forKey: .showsReturnTime
            ) ?? true,
            mainDisplayRole: try c.decodeIfPresent(
                String.self,
                forKey: .mainDisplayRole
            ),
            secondaryDisplayRole: try c.decodeIfPresent(
                String.self,
                forKey: .secondaryDisplayRole
            )
        )
    }

    public func sanitized() -> CurtainSceneProfile {
        CurtainSceneProfile(
            protectionMinutes: protectionMinutes,
            usesPresentation: usesPresentation,
            backgroundImagePath: backgroundImagePath,
            clockStyle: clockStyle,
            message: message,
            showsReturnTime: showsReturnTime,
            mainDisplayRole: mainDisplayRole,
            secondaryDisplayRole: secondaryDisplayRole
        )
    }

    private static func validRole(_ raw: String?) -> String? {
        guard let raw, let role = CurtainDisplayRole(rawValue: raw) else {
            return nil
        }
        return role.rawValue
    }
}

/// 菜单栏里的一键保护预设。场景只决定本次会话的时长和展示策略，
/// 不会改写用户保存的展示模式、背景或屏幕角色。
public enum CurtainScene: String, CaseIterable, Codable, Hashable {
    case away
    case meeting
    case guest
    case focus

    public var title: String {
        switch self {
        case .away: return "离开"
        case .meeting: return "会议"
        case .guest: return "访客"
        case .focus: return "专注"
        }
    }

    public var detail: String {
        switch self {
        case .away: return "展示时钟，适合长时间离座。"
        case .meeting: return "强制纯黑幕帘，适合投屏或旁人经过。"
        case .guest: return "展示时钟，适合短时间离开。"
        case .focus: return "强制纯黑幕帘，保持长时间免打扰。"
        }
    }

    public var symbol: String {
        switch self {
        case .away: return "figure.walk"
        case .meeting: return "person.2.fill"
        case .guest: return "person.crop.circle"
        case .focus: return "scope"
        }
    }

    public var defaultProtectionMinutes: Int {
        switch self {
        case .away: return 120
        case .meeting: return 60
        case .guest: return 30
        case .focus: return 90
        }
    }

    /// 每个场景使用独立数字键，避免和主快捷键及系统常用快捷键冲突。
    public var defaultHotkey: SceneHotkey {
        let keyCode: Int64
        switch self {
        case .away: keyCode = 18 // 1
        case .meeting: keyCode = 19 // 2
        case .guest: keyCode = 20 // 3
        case .focus: keyCode = 21 // 4
        }
        return SceneHotkey(
            keyCode: keyCode,
            modifiers: HotkeyPolicy.modifiers
        )
    }

    public var defaultProfile: CurtainSceneProfile {
        switch self {
        case .away:
            return CurtainSceneProfile(
                protectionMinutes: defaultProtectionMinutes,
                usesPresentation: true,
                message: "离开中",
                showsReturnTime: true
            )
        case .meeting:
            return CurtainSceneProfile(
                protectionMinutes: defaultProtectionMinutes,
                usesPresentation: false,
                message: "会议中",
                showsReturnTime: true
            )
        case .guest:
            return CurtainSceneProfile(
                protectionMinutes: defaultProtectionMinutes,
                usesPresentation: true,
                message: "访客模式",
                showsReturnTime: true
            )
        case .focus:
            return CurtainSceneProfile(
                protectionMinutes: defaultProtectionMinutes,
                usesPresentation: false,
                message: "专注中",
                showsReturnTime: true
            )
        }
    }

    public static func durationText(minutes: Int) -> String {
        let bounded = min(1440, max(0, minutes))
        if bounded == 0 { return "不限时" }
        if bounded % 60 == 0 { return "\(bounded / 60) 小时" }
        return "\(bounded) 分钟"
    }
}
