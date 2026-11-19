import CoreGraphics
import Foundation
import Testing
@testable import CurtainKit

@Suite("Presentation preview")
struct PresentationPreviewTests {
    private let screen = ScreenSnapshot(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        scale: 2,
        isMain: true
    )

    @Test("Preview refuses to start without a display")
    func noDisplay() {
        let session = PresentationPreviewSession()
        let error = session.start(
            screens: [],
            configuration: PresentationPreviewConfiguration(
                color: .black,
                imagePath: nil,
                clockStyle: .digital
            ),
            completion: { _ in }
        )
        #expect(error == .noScreens)
        #expect(!session.isActive)
    }

    @Test("Preview refuses unreadable background files before creating windows")
    func unreadableImage() {
        let session = PresentationPreviewSession()
        let error = session.start(
            screens: [screen],
            configuration: PresentationPreviewConfiguration(
                color: .black,
                imagePath: "/tmp/curtain-missing-background.png",
                clockStyle: .digital
            ),
            completion: { _ in }
        )
        #expect(error == .imageUnreadable)
        #expect(!session.isActive)
    }
}
