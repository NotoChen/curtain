import Foundation
import CoreGraphics

/// 运行配置。只保留用户真正会调的东西；截图目录、码率这些属于命令行参数，不在这里。
/// 新增字段全部带默认值，老配置文件可以直接升级（未知字段自动忽略）。
public struct CurtainConfig: Codable, Equatable {
    /// 长按 Esc 多少秒后弹出 Touch ID。
    public var holdToAuthSeconds: Double
    /// 双击 Esc 的判定窗口。两次物理 Esc 在这个时间内按下会直接请求 Touch ID。
    public var doubleEscapeSeconds: Double
    /// 开发兜底：入幕后多少秒自动撤幕，0 表示关闭（默认关闭）。
    public var safetyTimeoutSeconds: Double
    /// 幕帘期间是否隐藏鼠标指针。
    public var hideCursorDuringCurtain: Bool
    /// 输出层幕帘纯色，格式 #RRGGBB。
    public var curtainColor: String
    /// 起幕/撤幕快捷键。默认 ⌃⌥⌘C。
    public var hotkeyKeyCode: Int64
    public var hotkeyModifiers: UInt64
    /// 四个场景的独立全局快捷键；未写入的键使用场景默认值。
    public var sceneHotkeys: [String: SceneHotkey]
    /// 首次使用说明是否已经显示过。
    public var hasShownOnboarding: Bool
    /// 可选展示模式：用窗口显示背景图/状态，而不是默认的 gamma 输出层幕帘。
    /// 开启后只承诺常规 ScreenCaptureKit 采集看不到窗口。
    public var presentationModeEnabled: Bool
    /// 展示模式背景图路径；空字符串表示用纯色。
    public var presentationImagePath: String
    /// 展示模式时钟样式：digital / analog / editorial。
    public var presentationClockStyle: String
    /// 展示模式主屏角色：black / presentation。
    public var mainDisplayRole: String
    /// 展示模式副屏角色：black / presentation。
    public var secondaryDisplayRole: String
    /// 背景图焦点，0...1，默认居中。
    public var presentationFocusX: Double
    public var presentationFocusY: Double
    /// 背景图放大倍数，1...2。
    public var presentationZoom: Double
    /// 额外暗化，0...0.8。
    public var presentationDim: Double
    /// 空闲多久后自动起幕。
    public var idleAutoCurtainEnabled: Bool
    public var idleAutoCurtainSeconds: Double
    /// 每天定时保护窗口。
    public var scheduleEnabled: Bool
    public var scheduleStartMinutes: Int
    public var scheduleEndMinutes: Int
    /// bit 0 = 周一 ... bit 6 = 周日；0 表示未选择，仅在定时保护关闭时保留。
    public var scheduleWeekdays: Int
    /// 定时窗口结束后自动撤幕。默认关闭，避免无认证自动露出桌面。
    public var scheduleAutoExit: Bool
    /// 每次手动起幕的默认保护时长，0 表示不自动结束。
    public var defaultProtectionMinutes: Int
    /// 菜单栏场景的完整配置，键为 CurtainScene.rawValue。
    /// 未写入的键使用场景自带的默认配置。
    public var sceneProfiles: [String: CurtainSceneProfile]
    /// 幕帘期间允许合盖继续运行的系统电源断言。
    public var clamshellModeEnabled: Bool

    public init(holdToAuthSeconds: Double = 2.0,
                doubleEscapeSeconds: Double = 0.7,
                safetyTimeoutSeconds: Double = 0,
                hideCursorDuringCurtain: Bool = true,
                curtainColor: String = "#000000",
                hotkeyKeyCode: Int64 = HotkeyPolicy.keyCode,
                hotkeyModifiers: UInt64 = HotkeyPolicy.modifiers.rawValue,
                sceneHotkeys: [String: SceneHotkey] = [:],
                hasShownOnboarding: Bool = false,
                presentationModeEnabled: Bool = false,
                presentationImagePath: String = "",
                presentationClockStyle: String =
                    PresentationClockStyle.digital.rawValue,
                mainDisplayRole: String =
                    CurtainDisplayRole.presentation.rawValue,
                secondaryDisplayRole: String =
                    CurtainDisplayRole.presentation.rawValue,
                presentationFocusX: Double = 0.5,
                presentationFocusY: Double = 0.5,
                presentationZoom: Double = 1,
                presentationDim: Double = 0,
                idleAutoCurtainEnabled: Bool = false,
                idleAutoCurtainSeconds: Double = 600,
                scheduleEnabled: Bool = false,
                scheduleStartMinutes: Int = 9 * 60,
                scheduleEndMinutes: Int = 18 * 60,
                scheduleWeekdays: Int = 0b1111111,
                scheduleAutoExit: Bool = false,
                defaultProtectionMinutes: Int = 0,
                sceneProfiles: [String: CurtainSceneProfile] = [:],
                clamshellModeEnabled: Bool = false) {
        self.holdToAuthSeconds = holdToAuthSeconds
        self.doubleEscapeSeconds = doubleEscapeSeconds
        self.safetyTimeoutSeconds = safetyTimeoutSeconds
        self.hideCursorDuringCurtain = hideCursorDuringCurtain
        self.curtainColor = CurtainColor(hex: curtainColor)?.hex ?? CurtainColor.black.hex
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.sceneHotkeys = Self.sanitizeSceneHotkeys(sceneHotkeys)
        self.hasShownOnboarding = hasShownOnboarding
        self.presentationModeEnabled = presentationModeEnabled
        self.presentationImagePath = presentationImagePath
        self.presentationClockStyle = PresentationClockStyle
            .storedValue(presentationClockStyle)
            .rawValue
        self.mainDisplayRole = CurtainDisplayRole
            .storedValue(mainDisplayRole)
            .rawValue
        self.secondaryDisplayRole = CurtainDisplayRole
            .storedValue(secondaryDisplayRole)
            .rawValue
        self.presentationFocusX = Self.clamp(presentationFocusX, 0...1, fallback: 0.5)
        self.presentationFocusY = Self.clamp(presentationFocusY, 0...1, fallback: 0.5)
        self.presentationZoom = Self.clamp(presentationZoom, 1...2, fallback: 1)
        self.presentationDim = Self.clamp(presentationDim, 0...0.8, fallback: 0)
        self.idleAutoCurtainEnabled = idleAutoCurtainEnabled
        self.idleAutoCurtainSeconds = Self.clamp(
            idleAutoCurtainSeconds,
            60...86_400,
            fallback: 600
        )
        self.scheduleEnabled = scheduleEnabled
        self.scheduleStartMinutes = min(1439, max(0, scheduleStartMinutes))
        self.scheduleEndMinutes = min(1439, max(0, scheduleEndMinutes))
        self.scheduleWeekdays = min(0b1111111, max(0, scheduleWeekdays))
        self.scheduleAutoExit = scheduleAutoExit
        self.defaultProtectionMinutes = min(1440, max(0, defaultProtectionMinutes))
        self.sceneProfiles = Self.sanitizeSceneProfiles(sceneProfiles)
        self.clamshellModeEnabled = clamshellModeEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case holdToAuthSeconds, doubleEscapeSeconds, safetyTimeoutSeconds
        case hideCursorDuringCurtain, curtainColor
        case hotkeyKeyCode, hotkeyModifiers
        case sceneHotkeys
        case hasShownOnboarding
        case presentationModeEnabled, presentationImagePath, presentationClockStyle
        case mainDisplayRole, secondaryDisplayRole
        case presentationFocusX, presentationFocusY, presentationZoom, presentationDim
        case idleAutoCurtainEnabled, idleAutoCurtainSeconds
        case scheduleEnabled, scheduleStartMinutes, scheduleEndMinutes
        case scheduleWeekdays, scheduleAutoExit
        case defaultProtectionMinutes, sceneProfiles, clamshellModeEnabled
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case sceneProtectionMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hold = try c.decodeIfPresent(Double.self, forKey: .holdToAuthSeconds) ?? 2.0
        let doubleEscape = try c.decodeIfPresent(Double.self, forKey: .doubleEscapeSeconds) ?? 0.7
        let safety = try c.decodeIfPresent(Double.self, forKey: .safetyTimeoutSeconds) ?? 0
        holdToAuthSeconds = hold.isFinite ? min(5.0, max(1.0, hold)) : 2.0
        doubleEscapeSeconds = doubleEscape.isFinite ? min(1.5, max(0.3, doubleEscape)) : 0.7
        safetyTimeoutSeconds = safety.isFinite ? min(86_400, max(0, safety)) : 0
        hideCursorDuringCurtain = try c.decodeIfPresent(Bool.self, forKey: .hideCursorDuringCurtain) ?? true
        let color = try c.decodeIfPresent(String.self, forKey: .curtainColor) ?? CurtainColor.black.hex
        curtainColor = CurtainColor(hex: color)?.hex ?? CurtainColor.black.hex
        let keyCode = try c.decodeIfPresent(Int64.self, forKey: .hotkeyKeyCode) ?? HotkeyPolicy.keyCode
        let rawModifiers = try c.decodeIfPresent(UInt64.self, forKey: .hotkeyModifiers)
            ?? HotkeyPolicy.modifiers.rawValue
        let binding = HotkeyBinding(
            keyCode: keyCode,
            modifiers: CGEventFlags(rawValue: rawModifiers)
        )
        if binding.isValid {
            hotkeyKeyCode = binding.keyCode
            hotkeyModifiers = binding.modifiers.rawValue
        } else {
            hotkeyKeyCode = HotkeyPolicy.keyCode
            hotkeyModifiers = HotkeyPolicy.modifiers.rawValue
        }
        sceneHotkeys = Self.sanitizeSceneHotkeys(
            try c.decodeIfPresent(
                [String: SceneHotkey].self,
                forKey: .sceneHotkeys
            ) ?? [:]
        )
        hasShownOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasShownOnboarding) ?? false
        presentationModeEnabled = try c.decodeIfPresent(
            Bool.self,
            forKey: .presentationModeEnabled
        ) ?? false
        let path = try c.decodeIfPresent(String.self, forKey: .presentationImagePath) ?? ""
        presentationImagePath = path.count <= 4096 ? path : ""
        let style = try c.decodeIfPresent(String.self, forKey: .presentationClockStyle)
            ?? PresentationClockStyle.digital.rawValue
        presentationClockStyle = PresentationClockStyle
            .storedValue(style)
            .rawValue
        mainDisplayRole = CurtainDisplayRole.storedValue(
            try c.decodeIfPresent(String.self, forKey: .mainDisplayRole) ?? ""
        ).rawValue
        secondaryDisplayRole = CurtainDisplayRole.storedValue(
            try c.decodeIfPresent(String.self, forKey: .secondaryDisplayRole) ?? ""
        ).rawValue
        presentationFocusX = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .presentationFocusX) ?? 0.5,
            0...1,
            fallback: 0.5
        )
        presentationFocusY = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .presentationFocusY) ?? 0.5,
            0...1,
            fallback: 0.5
        )
        presentationZoom = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .presentationZoom) ?? 1,
            1...2,
            fallback: 1
        )
        presentationDim = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .presentationDim) ?? 0,
            0...0.8,
            fallback: 0
        )
        idleAutoCurtainEnabled = try c.decodeIfPresent(
            Bool.self,
            forKey: .idleAutoCurtainEnabled
        ) ?? false
        idleAutoCurtainSeconds = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .idleAutoCurtainSeconds) ?? 600,
            60...86_400,
            fallback: 600
        )
        scheduleEnabled = try c.decodeIfPresent(
            Bool.self,
            forKey: .scheduleEnabled
        ) ?? false
        scheduleStartMinutes = min(1439, max(0, try c.decodeIfPresent(
            Int.self,
            forKey: .scheduleStartMinutes
        ) ?? 9 * 60))
        scheduleEndMinutes = min(1439, max(0, try c.decodeIfPresent(
            Int.self,
            forKey: .scheduleEndMinutes
        ) ?? 18 * 60))
        scheduleWeekdays = min(0b1111111, max(0, try c.decodeIfPresent(
            Int.self,
            forKey: .scheduleWeekdays
        ) ?? 0b1111111))
        scheduleAutoExit = try c.decodeIfPresent(
            Bool.self,
            forKey: .scheduleAutoExit
        ) ?? false
        defaultProtectionMinutes = min(1440, max(0, try c.decodeIfPresent(
            Int.self,
            forKey: .defaultProtectionMinutes
        ) ?? 0))
        if let decoded = try c.decodeIfPresent(
            [String: CurtainSceneProfile].self,
            forKey: .sceneProfiles
        ) {
            sceneProfiles = Self.sanitizeSceneProfiles(decoded)
        } else {
            let legacyContainer = try decoder.container(
                keyedBy: LegacyCodingKeys.self
            )
            let legacy = try legacyContainer.decodeIfPresent(
                [String: Int].self,
                forKey: .sceneProtectionMinutes
            ) ?? [:]
            var migrated: [String: CurtainSceneProfile] = [:]
            for (key, minutes) in legacy {
                guard let scene = CurtainScene(rawValue: key) else { continue }
                var profile = scene.defaultProfile
                profile.protectionMinutes = min(1440, max(0, minutes))
                migrated[key] = profile
            }
            sceneProfiles = migrated
        }
        clamshellModeEnabled = try c.decodeIfPresent(
            Bool.self,
            forKey: .clamshellModeEnabled
        ) ?? false
    }

    public func displayRole(isMain: Bool) -> CurtainDisplayRole {
        guard presentationModeEnabled else { return .black }
        return CurtainDisplayRole.storedValue(
            isMain ? mainDisplayRole : secondaryDisplayRole
        )
    }

    /// 场景可以覆盖主/副屏角色；未覆盖时沿用全局配置。
    public func displayRole(for scene: CurtainScene?,
                            isMain: Bool) -> CurtainDisplayRole {
        guard presentationModeEnabled else { return .black }
        if let scene {
            let profile = sceneProfile(for: scene)
            let raw = isMain
                ? profile.mainDisplayRole
                : profile.secondaryDisplayRole
            if let raw, let role = CurtainDisplayRole(rawValue: raw) {
                return role
            }
        }
        return displayRole(isMain: isMain)
    }

    public func sceneProfile(for scene: CurtainScene) -> CurtainSceneProfile {
        sceneProfiles[scene.rawValue] ?? scene.defaultProfile
    }

    public func sceneHotkey(for scene: CurtainScene) -> SceneHotkey {
        sceneHotkeys[scene.rawValue] ?? scene.defaultHotkey
    }

    public func protectionMinutes(for scene: CurtainScene) -> Int {
        sceneProfile(for: scene).protectionMinutes
    }

    private static func sanitizeSceneHotkeys(
        _ raw: [String: SceneHotkey]
    ) -> [String: SceneHotkey] {
        var result: [String: SceneHotkey] = [:]
        for (key, value) in raw {
            guard CurtainScene(rawValue: key) != nil, value.isValid else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private static func sanitizeSceneProfiles(
        _ raw: [String: CurtainSceneProfile]
    ) -> [String: CurtainSceneProfile] {
        var result: [String: CurtainSceneProfile] = [:]
        for (key, value) in raw {
            guard CurtainScene(rawValue: key) != nil else { continue }
            result[key] = value.sanitized()
        }
        return result
    }

    private static func clamp(_ value: Double,
                              _ range: ClosedRange<Double>,
                              fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    public static let `default` = CurtainConfig()

    public static func load() -> CurtainConfig {
        guard let data = try? Data(contentsOf: Paths.configURL),
              let cfg = try? JSONDecoder().decode(CurtainConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    @discardableResult
    public func save() -> String? {
        guard Paths.ensureSupportDir() else {
            return "无法创建 \(Paths.supportDir.path)"
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(self)
            try data.write(to: Paths.configURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Paths.configURL.path
            )
            return nil
        } catch {
            return "写入 \(Paths.configURL.path) 失败：\(error)"
        }
    }
}
