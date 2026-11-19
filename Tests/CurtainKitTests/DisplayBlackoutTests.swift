import CoreGraphics
import Testing
@testable import CurtainKit

private final class FakeGamma: GammaControlling {
    var tables: [CGDirectDisplayID: GammaTable]
    var blacked: Set<CGDirectDisplayID> = []
    var setUniformFailures: Set<CGDirectDisplayID> = []
    var setUniformCalls = 0
    var uniformSampleCounts: [CGDirectDisplayID: UInt32] = [:]
    var colors: [CGDirectDisplayID: CurtainColor] = [:]
    var restoreAllCalls = 0

    init(tables: [CGDirectDisplayID: GammaTable]) {
        self.tables = tables
    }

    func read(_ displayID: CGDirectDisplayID) -> GammaTable? {
        tables[displayID]
    }

    func setUniform(_ displayID: CGDirectDisplayID, sampleCount: UInt32, color: CurtainColor) -> Bool {
        setUniformCalls += 1
        guard !setUniformFailures.contains(displayID) else { return false }
        uniformSampleCounts[displayID] = sampleCount
        colors[displayID] = color
        blacked.insert(displayID)
        return true
    }

    func set(_ table: GammaTable, for displayID: CGDirectDisplayID) -> Bool {
        tables[displayID] = table
        blacked.remove(displayID)
        return true
    }

    func isUniform(_ displayID: CGDirectDisplayID, color: CurtainColor) -> Bool {
        blacked.contains(displayID) && colors[displayID] == color
    }

    func restoreAll() {
        restoreAllCalls += 1
    }
}

@Suite("Display blackout")
struct DisplayBlackoutTests {
    private func table(_ value: CGGammaValue) -> GammaTable {
        GammaTable(red: [value], green: [value], blue: [value], count: 1)
    }

    @Test("Apply, refresh, topology change and restore")
    func applyRefreshAndRestore() {
        let gamma = FakeGamma(tables: [
            1: table(0.4),
            2: table(0.5),
            3: table(0.6),
        ])
        let blackout = DisplayBlackout(gamma: gamma)

        #expect(blackout.apply(to: [1, 2]))
        #expect(blackout.blackedDisplayIDs == [1, 2])
        #expect(gamma.blacked == [1, 2])

        gamma.blacked.remove(2)
        let callsBeforeRefresh = gamma.setUniformCalls
        blackout.refresh()
        #expect(gamma.setUniformCalls == callsBeforeRefresh + 1)
        #expect(gamma.blacked.contains(2))

        #expect(blackout.apply(to: [2, 3]))
        #expect(blackout.blackedDisplayIDs == [2, 3])
        #expect(gamma.tables[1] == table(0.4))
        #expect(gamma.tables[2] == table(0.5))
        #expect(gamma.tables[3] == table(0.6))

        blackout.restoreAll()
        #expect(blackout.blackedDisplayIDs.isEmpty)
        #expect(gamma.blacked.isEmpty)
        #expect(gamma.tables[2] == table(0.5))
        #expect(gamma.tables[3] == table(0.6))
    }

    @Test("A display whose gamma cannot be changed is not marked black")
    func failedDisplayIsNotMarked() {
        let gamma = FakeGamma(tables: [1: table(0.4), 4: table(0.8)])
        gamma.setUniformFailures = [4]
        let blackout = DisplayBlackout(gamma: gamma)

        #expect(blackout.apply(to: [1, 4]))
        #expect(blackout.blackedDisplayIDs == [1])
        #expect(gamma.blacked == [1])
    }

    @Test("The original gamma sample count is restored, not truncated")
    func preservesGammaResolution() {
        let original = GammaTable(
            red: [CGGammaValue](repeating: 0.4, count: 1024),
            green: [CGGammaValue](repeating: 0.4, count: 1024),
            blue: [CGGammaValue](repeating: 0.4, count: 1024),
            count: 1024
        )
        let gamma = FakeGamma(tables: [1: original])
        let blackout = DisplayBlackout(gamma: gamma)

        #expect(blackout.apply(to: [1]))
        #expect(gamma.uniformSampleCounts[1] == 1024)

        blackout.restoreAll()
        #expect(gamma.tables[1]?.count == 1024)
        #expect(gamma.tables[1] == original)
    }

    @Test("A color change rewrites gamma without restoring the desktop")
    func changesColorInPlace() {
        let original = table(0.4)
        let gamma = FakeGamma(tables: [1: original])
        let blackout = DisplayBlackout(gamma: gamma)
        let red = CurtainColor(red: 0.4, green: 0.05, blue: 0.05)
        let blue = CurtainColor(red: 0.05, green: 0.05, blue: 0.4)

        #expect(blackout.apply(to: [1], color: red))
        #expect(gamma.colors[1] == red)
        #expect(gamma.tables[1] == original)

        #expect(blackout.apply(to: [1], color: blue))
        #expect(gamma.colors[1] == blue)
        #expect(gamma.tables[1] == original)
        #expect(blackout.activeColor == blue)
    }

}
