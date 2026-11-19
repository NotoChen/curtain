import CoreGraphics
import Foundation

/// 显示器输出层幕帘。
///
/// gamma table 作用在显示输出阶段，位于 framebuffer 之后。把 gamma 全置为同一
/// 纯色后，人眼看到的是整屏纯色，但任何读取 framebuffer 的截图/录屏仍然拿到真实桌面。
/// macOS 会在进程退出、显示器重配和唤醒时恢复 gamma；这里仍保存原表并主动恢复。
struct GammaTable: Equatable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]
    var count: UInt32
}

protocol GammaControlling {
    func read(_ displayID: CGDirectDisplayID) -> GammaTable?
    func setUniform(_ displayID: CGDirectDisplayID, sampleCount: UInt32, color: CurtainColor) -> Bool
    func set(_ table: GammaTable, for displayID: CGDirectDisplayID) -> Bool
    func isUniform(_ displayID: CGDirectDisplayID, color: CurtainColor) -> Bool
    func restoreAll()
}

struct SystemGamma: GammaControlling {
    /// 真实显示器常见 256/1024 个采样点。读取容量不能按 256 截断，
    /// 否则撤幕时会把原始色表按较低分辨率写回，留下可见色偏。
    private static let sampleCapacity = 4096

    func read(_ displayID: CGDirectDisplayID) -> GammaTable? {
        var red = [CGGammaValue](repeating: 1, count: Self.sampleCapacity)
        var green = red
        var blue = red
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(
            displayID,
            UInt32(Self.sampleCapacity),
            &red,
            &green,
            &blue,
            &count
        )
        guard result == .success, count > 0, count <= UInt32(Self.sampleCapacity) else { return nil }
        return GammaTable(
            red: Array(red.prefix(Int(count))),
            green: Array(green.prefix(Int(count))),
            blue: Array(blue.prefix(Int(count))),
            count: count
        )
    }

    func setUniform(_ displayID: CGDirectDisplayID, sampleCount: UInt32, color: CurtainColor) -> Bool {
        guard sampleCount > 0, sampleCount <= UInt32(Self.sampleCapacity) else { return false }
        let red = [CGGammaValue](repeating: CGGammaValue(color.red), count: Int(sampleCount))
        let green = [CGGammaValue](repeating: CGGammaValue(color.green), count: Int(sampleCount))
        let blue = [CGGammaValue](repeating: CGGammaValue(color.blue), count: Int(sampleCount))
        return CGSetDisplayTransferByTable(
            displayID,
            sampleCount,
            red,
            green,
            blue
        ) == .success
    }

    func set(_ table: GammaTable, for displayID: CGDirectDisplayID) -> Bool {
        guard table.count > 0 else { return false }
        return CGSetDisplayTransferByTable(
            displayID,
            table.count,
            table.red,
            table.green,
            table.blue
        ) == .success
    }

    func isUniform(_ displayID: CGDirectDisplayID, color: CurtainColor) -> Bool {
        guard let table = read(displayID), table.count > 0 else { return false }
        let tolerance: CGGammaValue = 0.003
        return table.red.allSatisfy { abs($0 - CGGammaValue(color.red)) <= tolerance }
            && table.green.allSatisfy { abs($0 - CGGammaValue(color.green)) <= tolerance }
            && table.blue.allSatisfy { abs($0 - CGGammaValue(color.blue)) <= tolerance }
    }

    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }
}

/// 按 displayID 维护 gamma 黑幕，并保存原始 gamma 供认证/撤幕时恢复。
final class DisplayBlackout {
    private let gamma: GammaControlling
    private var savedTables: [CGDirectDisplayID: GammaTable] = [:]
    private(set) var blackedDisplayIDs: Set<CGDirectDisplayID> = []
    private(set) var activeColor: CurtainColor = .black

    init(gamma: GammaControlling = SystemGamma()) {
        self.gamma = gamma
    }

    var isActive: Bool {
        !blackedDisplayIDs.isEmpty
    }

    /// 对指定显示器应用输出层纯色；不再存在的显示器会恢复原 gamma。
    @discardableResult
    func apply(to displayIDs: [CGDirectDisplayID], color: CurtainColor = .black) -> Bool {
        activeColor = color
        let targets = Set(displayIDs)
        for displayID in blackedDisplayIDs.subtracting(targets) {
            restore(displayID)
        }

        for displayID in targets {
            if blackedDisplayIDs.contains(displayID) {
                guard gamma.isUniform(displayID, color: color) else {
                    // 系统在唤醒/重配显示器时可能重置 gamma；颜色变化也走这里，
                    // 用原始采样点数重涂，期间不恢复原表，避免短暂露出桌面。
                    let count = savedTables[displayID]?.count ?? 0
                    _ = gamma.setUniform(displayID, sampleCount: count, color: color)
                    if !gamma.isUniform(displayID, color: color) {
                        if let original = savedTables.removeValue(forKey: displayID) {
                            _ = gamma.set(original, for: displayID)
                        }
                        blackedDisplayIDs.remove(displayID)
                    }
                    continue
                }
                continue
            }

            guard let original = gamma.read(displayID) else { continue }
            savedTables[displayID] = original
            guard gamma.setUniform(displayID, sampleCount: original.count, color: color),
                  gamma.isUniform(displayID, color: color) else {
                _ = gamma.set(original, for: displayID)
                savedTables.removeValue(forKey: displayID)
                continue
            }
            blackedDisplayIDs.insert(displayID)
        }
        return isActive
    }

    /// macOS 在唤醒/显示器重配后会重置 gamma，定时检查并按需重涂。
    @discardableResult
    func refresh() -> Bool {
        var allBlack = true
        for displayID in blackedDisplayIDs where !gamma.isUniform(displayID, color: activeColor) {
            let count = savedTables[displayID]?.count ?? 0
            _ = gamma.setUniform(displayID, sampleCount: count, color: activeColor)
            if !gamma.isUniform(displayID, color: activeColor) {
                allBlack = false
            }
        }
        return allBlack
    }

    /// 不把屏幕变黑，只做一次“读原表并用同一张表写回”的能力探测。
    /// 用于 doctor 判断当前显示器是否支持输出层黑幕。
    static func supportsBlackout(_ displayID: CGDirectDisplayID) -> Bool {
        let gamma = SystemGamma()
        guard let table = gamma.read(displayID) else { return false }
        return gamma.set(table, for: displayID)
    }

    func restoreAll() {
        for displayID in Array(blackedDisplayIDs) {
            restore(displayID)
        }
        savedTables.removeAll()
        blackedDisplayIDs.removeAll()
        activeColor = .black
    }

    private func restore(_ displayID: CGDirectDisplayID) {
        if let original = savedTables.removeValue(forKey: displayID) {
            if !gamma.set(original, for: displayID) {
                gamma.restoreAll()
            }
        }
        blackedDisplayIDs.remove(displayID)
    }
}
