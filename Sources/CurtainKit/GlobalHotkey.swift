import CoreGraphics
import Foundation

public struct HotkeyBinding: Equatable {
    public var keyCode: Int64
    public var modifiers: CGEventFlags

    public init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(HotkeyPolicy.relevantModifiers)
    }

    public var isValid: Bool {
        let required = modifiers.intersection([.maskControl, .maskAlternate, .maskCommand])
        return (0...127).contains(keyCode) && !required.isEmpty
    }
}

/// 场景快捷键的持久化值。与主快捷键分开保存，避免场景配置影响起幕/撤幕路径。
public struct SceneHotkey: Codable, Equatable {
    public var keyCode: Int64
    public var modifiers: UInt64

    public init(keyCode: Int64, modifiers: CGEventFlags) {
        let binding = HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers
        )
        self.keyCode = binding.keyCode
        self.modifiers = binding.modifiers.rawValue
    }

    public init(binding: HotkeyBinding) {
        self.init(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    public var binding: HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: CGEventFlags(rawValue: modifiers)
        )
    }

    public var isValid: Bool {
        binding.isValid
    }

    public var displayString: String {
        binding.displayString
    }
}

public extension HotkeyBinding {
    var displayString: String {
        HotkeyPolicy.displayString(
            keyCode: keyCode,
            modifiers: modifiers
        )
    }
}

/// 快捷键匹配规则单独抽出来，避免事件 tap 的边界条件只能靠真机试。
public enum HotkeyPolicy {
    public static let defaultKeyCode: Int64 = 8 // kVK_ANSI_C
    public static let defaultModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    public static let keyCode: Int64 = defaultKeyCode
    public static let modifiers: CGEventFlags = defaultModifiers
    public static let relevantModifiers: CGEventFlags = [
        .maskControl, .maskAlternate, .maskCommand, .maskShift,
    ]

    public static func matches(eventKeyCode: Int64,
                               flags: CGEventFlags,
                               sourcePID: Int32,
                               expectedKeyCode: Int64 = defaultKeyCode,
                               expectedModifiers: CGEventFlags = defaultModifiers) -> Bool {
        let relevant = flags.intersection(relevantModifiers)
        let expected = expectedModifiers.intersection(relevantModifiers)
        return sourcePID == 0 && eventKeyCode == expectedKeyCode && relevant == expected
    }

    public static func displayString(keyCode: Int64, modifiers: CGEventFlags) -> String {
        let normalized = modifiers.intersection(relevantModifiers)
        var result = ""
        if normalized.contains(.maskControl) { result += "⌃" }
        if normalized.contains(.maskAlternate) { result += "⌥" }
        if normalized.contains(.maskShift) { result += "⇧" }
        if normalized.contains(.maskCommand) { result += "⌘" }
        return result + keyName(for: keyCode)
    }

    private static func keyName(for keyCode: Int64) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 79: return "F18"
        case 80: return "F19"
        case 64: return "F17"
        case 90: return "Keypad 8"
        default: return "Key \(keyCode)"
        }
    }
}

/// 全局起幕帘快捷键。用 session 级事件 tap 消费热键，避免快捷键里的 `c`
/// 漏进当前应用；物理来源、非合成事件才触发。
public final class GlobalHotkey {
    public var onPressed: (() -> Void)?
    /// tap 被系统禁用且无法恢复时调用。调用方应尝试重建监听。
    public var onUnavailable: (() -> Void)?

    private let keyCode: Int64
    private let modifiers: CGEventFlags
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var failureReported = false

    public init(keyCode: Int64 = HotkeyPolicy.keyCode,
                modifiers: CGEventFlags = HotkeyPolicy.modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(HotkeyPolicy.relevantModifiers)
    }

    public var isActive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(refcon).takeUnretainedValue()
                return hotkey.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.tap = tap
        runLoopSource = source
        failureReported = false
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            return false
        }
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) {
                    reportUnavailable()
                } else {
                    failureReported = false
                }
            }
            return nil
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        let sourcePID = Int32(event.getIntegerValueField(.eventSourceUnixProcessID))
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard HotkeyPolicy.matches(
            eventKeyCode: key,
            flags: event.flags,
            sourcePID: sourcePID,
            expectedKeyCode: keyCode,
            expectedModifiers: modifiers
        ) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            DispatchQueue.main.async { [weak self] in
                self?.onPressed?()
            }
        }
        return nil
    }

    private func reportUnavailable() {
        guard !failureReported else { return }
        failureReported = true
        DispatchQueue.main.async { [weak self] in
            self?.onUnavailable?()
        }
    }

    deinit { stop() }
}
