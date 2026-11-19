import AppKit
import Foundation
import ImageIO

/// 展示模式背景图按目标屏幕像素解码；同一路径只保留一份可复用的 CGImage。
public enum PresentationBackgroundLoader {
    private final class CacheEntry: NSObject {
        let image: CGImage
        let pixelSize: CGSize

        init(image: CGImage, pixelSize: CGSize) {
            self.image = image
            self.pixelSize = pixelSize
        }
    }

    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 4
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    public static func recommendedPixelSize(for screens: [ScreenSnapshot]) -> CGFloat {
        let maximum = screens.map { screen in
            max(screen.frame.width, screen.frame.height) * max(1, screen.scale)
        }.max() ?? 1600
        return min(8192, max(1024, ceil(maximum)))
    }

    public static func isLoadable(path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            nil
        ) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    public static func load(path: String, maxPixelSize: CGFloat) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let target = min(8192, max(256, ceil(maxPixelSize)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        let entry = CacheEntry(
            image: image,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
        let cost = image.bytesPerRow * image.height
        cache.setObject(entry, forKey: key, cost: cost)
        return image
    }

    private static func cacheKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        let bucket = Int(ceil(max(256, maxPixelSize) / 256) * 256)
        return "\(url.path)|\(modified)|\(size)|\(bucket)" as NSString
    }
}

/// 只负责展示的等比铺满视图；图片由调用方按屏幕像素预先解码。
final class AspectFillImageView: NSView {
    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
    }

    func apply(image: CGImage?, focus: CGPoint, zoom: CGFloat) {
        self.image = image
        guard image != nil else { return }
        let boundedZoom = min(2, max(1, zoom))
        let visible = 1 / boundedZoom
        let x = min(1 - visible, max(0, focus.x - visible / 2))
        let y = min(1 - visible, max(0, focus.y - visible / 2))
        layer?.contentsRect = CGRect(x: x, y: y, width: visible, height: visible)
    }
}
