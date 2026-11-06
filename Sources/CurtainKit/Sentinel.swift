import Foundation
import IOKit.pwr_mgt

/// 幕帘期间必须保持屏幕常亮：一旦显示器休眠，窗口 surface 失效，截图就是空白。
/// 同时压住系统闲置睡眠，避免整机睡过去。
/// 热角不需要处理——物理鼠标事件被吞掉，指针根本不会移到角落。
public final class Sentinel {
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var active = false

    public init() {}

    public func enable() {
        guard !active else { return }
        let reason = "Curtain: keep the session awake while the curtain is up" as CFString

        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
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
        active = (displayResult == kIOReturnSuccess) || (systemResult == kIOReturnSuccess)
    }

    public func disable() {
        guard active else { return }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
        displayAssertion = 0
        systemAssertion = 0
        active = false
    }
}

