import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// 幕帘期间必须保持屏幕常亮：一旦显示器休眠，窗口 surface 失效，截图就是空白。
/// 同时压住系统闲置睡眠，避免整机睡过去。
/// 热角不需要处理——物理鼠标事件被吞掉，指针根本不会移到角落。
public final class Sentinel {
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var active = false
    public private(set) var displayAssertionActive = false
    public private(set) var systemAssertionActive = false
    public private(set) var hasExternalDisplay = false
    public private(set) var lastError: String?
    public var preventsClamshellSleep = false {
        didSet {
            guard active, oldValue != preventsClamshellSleep else { return }
            updateClamshellAvailability()
        }
    }

    public init() {}

    public func enable() {
        guard !active else { return }
        let reason = "Curtain: keep the session awake while the curtain is up" as CFString

        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertion
        )
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemAssertion
        )
        displayAssertionActive = displayResult == kIOReturnSuccess
        systemAssertionActive = systemResult == kIOReturnSuccess
        active = displayAssertionActive || systemAssertionActive
        lastError = active
            ? nil
            : "无法创建显示器或系统防休眠断言"
        updateClamshellAvailability()
    }

    public func disable() {
        guard active else { return }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
        displayAssertion = 0
        systemAssertion = 0
        active = false
        displayAssertionActive = false
        systemAssertionActive = false
        hasExternalDisplay = false
    }

    public var clamshellStatus: String {
        guard preventsClamshellSleep else { return "关闭" }
        guard active else { return "电源断言未建立" }
        if hasExternalDisplay {
            return "已请求；外接显示器在位"
        }
        return "仅空闲断言；无外接屏时由 macOS 电源策略决定"
    }

    private func updateClamshellAvailability() {
        guard preventsClamshellSleep else {
            hasExternalDisplay = false
            return
        }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            hasExternalDisplay = false
            return
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            hasExternalDisplay = false
            return
        }
        hasExternalDisplay = displays.prefix(Int(count)).contains {
            CGDisplayIsBuiltin($0) == 0
        }
    }
}

