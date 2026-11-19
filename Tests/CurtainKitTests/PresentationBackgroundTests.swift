import AppKit
import Foundation
import Testing
@testable import CurtainKit

@Suite("Presentation background")
struct PresentationBackgroundTests {
    @Test("Recommended decode size follows the largest screen in pixels")
    func recommendedSize() {
        let screens = [
            ScreenSnapshot(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1680, height: 1050),
                scale: 2,
                isMain: true
            ),
            ScreenSnapshot(
                displayID: 2,
                frame: CGRect(x: 1680, y: 0, width: 1920, height: 1080),
                scale: 1,
                isMain: false
            ),
        ]
        #expect(
            PresentationBackgroundLoader.recommendedPixelSize(for: screens)
                == 3360
        )
    }

    @Test("Large images are decoded down to the requested pixel size")
    func downsample() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("curtain-background-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(makeImage(width: 1200, height: 600))
        let rep = NSBitmapImageRep(cgImage: source)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)

        #expect(PresentationBackgroundLoader.isLoadable(path: url.path))
        let image = try #require(
            PresentationBackgroundLoader.load(
                path: url.path,
                maxPixelSize: 512
            )
        )
        #expect(max(image.width, image.height) == 512)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
