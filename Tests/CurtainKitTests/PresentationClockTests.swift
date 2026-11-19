import Foundation
import Testing
@testable import CurtainKit

@Suite("Presentation clock")
struct PresentationClockTests {
    @Test("Clock status includes full date, seconds, weekday, lunar date and session time")
    func completeStatus() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 17,
            hour: 14,
            minute: 32,
            second: 5
        )))
        let startedAt = now.addingTimeInterval(-(1 * 3600 + 2 * 60 + 3))

        let status = PresentationClockFormatter.status(
            at: now,
            startedAt: startedAt,
            timeZone: timeZone
        )

        #expect(status.timeText == "14:32")
        #expect(status.secondsText == ":05")
        #expect(status.dateText == "2026年11月17日")
        #expect(status.weekdayText == "星期二")
        #expect(status.lunarText == "农历十月初九")
        #expect(status.elapsedText == "已保护 1:02:03")
    }

    @Test("All presentation styles are persisted by stable raw values")
    func stableStyles() {
        #expect(PresentationClockStyle.allCases == [.digital, .analog, .editorial])
        #expect(PresentationClockStyle.storedValue("analog") == .analog)
        #expect(PresentationClockStyle.storedValue("unknown") == .digital)
    }

    @Test("Status carries scene message and return time")
    func sceneCopy() {
        let status = PresentationClockFormatter.status(
            at: Date(timeIntervalSince1970: 0),
            startedAt: nil,
            messageText: "会议中",
            returnText: "预计 18:30 回来"
        )
        #expect(status.messageText == "会议中")
        #expect(status.returnText == "预计 18:30 回来")
    }
}
