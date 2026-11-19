import CoreGraphics
import Foundation
import IOKit

public enum CurtainDisplayRole: String, CaseIterable, Codable {
    case black
    case presentation

    public var displayName: String {
        switch self {
        case .black: return "幕帘"
        case .presentation: return "展示"
        }
    }

    public static func storedValue(_ raw: String) -> CurtainDisplayRole {
        CurtainDisplayRole(rawValue: raw) ?? .presentation
    }
}

public enum CurtainTrigger: String, Codable {
    case manual
    case idle
    case schedule
    case scene
    case timer
    case url
    case cli
}

public enum CurtainURLAction: String {
    case on
    case protect
    case off
    case status
    case settings
}

public struct CurtainURLCommand: Equatable {
    public let action: CurtainURLAction
    public let minutes: Int?

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "curtain" else { return nil }
        let raw = (url.host ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard let action = CurtainURLAction(rawValue: raw) else { return nil }
        self.action = action
        let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        if let rawMinutes = components?.queryItems?
            .first(where: { $0.name == "minutes" })?
            .value,
           let parsed = Int(rawMinutes) {
            minutes = min(1440, max(0, parsed))
        } else {
            minutes = nil
        }
    }
}

public enum CurtainAutomationPolicy {
    public static func shouldStartForIdle(
        enabled: Bool,
        idleSeconds: TimeInterval,
        threshold: TimeInterval
    ) -> Bool {
        enabled && threshold > 0 && idleSeconds >= threshold
    }

    /// 支持普通日间窗口和跨午夜窗口。跨午夜时，凌晨部分沿用前一天是否被选中。
    public static func scheduleContains(
        enabled: Bool,
        weekdays: Int,
        startMinutes: Int,
        endMinutes: Int,
        date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard enabled, (1...0b1111111).contains(weekdays) else { return false }
        let minute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let weekdayBit = weekdayBit(for: date, calendar: calendar)
        let previousBit = previousWeekdayBit(for: weekdayBit)
        if startMinutes < endMinutes {
            return (weekdays & weekdayBit) != 0
                && minute >= startMinutes
                && minute < endMinutes
        }
        if startMinutes > endMinutes {
            let beforeMidnight = (weekdays & weekdayBit) != 0
                && minute >= startMinutes
            let afterMidnight = (weekdays & previousBit) != 0
                && minute < endMinutes
            return beforeMidnight || afterMidnight
        }
        // 开始和结束相同视为选中日期的全天保护。
        return (weekdays & weekdayBit) != 0
    }

    public static func weekdayBit(
        for date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let mondayBased = (weekday + 5) % 7
        return 1 << mondayBased
    }

    private static func previousWeekdayBit(for bit: Int) -> Int {
        bit == 1 ? 0b1000000 : bit >> 1
    }
}

public enum InputIdleMonitor {
    public static func secondsSinceLastInput() -> TimeInterval {
        // IOHIDSystem 只反映真实 HID 活跃时间；CGEventSource 会把 agent
        // 合成事件也算进去，导致空闲起幕永远达不到阈值。
        if let hidIdle = hidIdleSeconds() {
            return hidIdle
        }
        let state = CGEventSourceStateID.combinedSessionState
        let eventTypes: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .mouseMoved,
        ]
        let values = eventTypes.map {
            CGEventSource.secondsSinceLastEventType(state, eventType: $0)
        }
        return max(0, values.min() ?? 0)
    }

    private static func hidIdleSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return nil
        }
        return max(0, value.doubleValue / 1_000_000_000)
    }
}
