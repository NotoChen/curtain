import AppKit
import CoreGraphics

/// 一块屏幕在某一时刻的稳定身份与几何信息。
/// 采集和控制都按 `displayID` 定位，不用 `NSScreen.screens` 的下标，
/// 避免热插拔或系统重排之后把第 0 块屏指到另一块屏。
public struct ScreenSnapshot: Equatable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let scale: CGFloat
    public let isMain: Bool

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat, isMain: Bool) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
        self.isMain = isMain
    }
}

public enum ScreenInventory {
    /// 只能在主线程读取，或在调用方显式切到主线程后读取。
    public static func current() -> [ScreenSnapshot] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return ScreenSnapshot(
                displayID: displayID,
                frame: screen.frame,
                scale: screen.backingScaleFactor,
                isMain: CGDisplayIsMain(displayID) != 0
            )
        }
    }

    public static func screen(for displayID: CGDirectDisplayID) -> ScreenSnapshot? {
        current().first { $0.displayID == displayID }
    }

    /// 兼容旧的 CLI 下标参数，但只在下标解析时短暂使用；
    /// 真正的采集和窗口管理始终保存稳定 ID。
    public static func screen(at index: Int) -> ScreenSnapshot? {
        let screens = current()
        guard screens.indices.contains(index) else { return nil }
        return screens[index]
    }
}
