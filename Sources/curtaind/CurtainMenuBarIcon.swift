import AppKit

enum CurtainGlyph {
    static func image(size: CGFloat = 18,
                      curtainOn: Bool = false,
                      authenticating: Bool = false,
                      recording: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawCurtain(in: rect, open: !curtainOn && !authenticating)
            if authenticating {
                drawLockBadge(in: rect)
            } else if recording {
                drawRecordingBadge(in: rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func brandImage(size: CGFloat = 48, filled: Bool = true) -> NSImage {
        let symbolName = filled ? "curtains.closed" : "curtains.open"
        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: size * 0.72, weight: .medium)
        ) else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let target = NSRect(
                x: rect.midX - symbol.size.width / 2,
                y: rect.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: target)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawCurtain(in rect: NSRect, open: Bool) {
        let scale = rect.width / 18
        NSColor.black.setFill()
        NSColor.black.setStroke()

        let rodY = rect.minY + 13.45 * scale
        let rod = NSBezierPath()
        rod.move(to: NSPoint(x: rect.minX + 2.3 * scale, y: rodY))
        rod.line(to: NSPoint(x: rect.minX + 15.7 * scale, y: rodY))
        rod.lineWidth = 1.2 * scale
        rod.lineCapStyle = .round
        rod.stroke()
        for x in [1.95, 16.05] {
            NSBezierPath(
                ovalIn: NSRect(
                    x: rect.minX + (x - 0.72) * scale,
                    y: rodY - 0.72 * scale,
                    width: 1.44 * scale,
                    height: 1.44 * scale
                )
            ).fill()
        }

        panelPath(in: rect, scale: scale, open: open, mirrored: false).fill()
        panelPath(in: rect, scale: scale, open: open, mirrored: true).fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.clear.setStroke()

        if !open {
            let seam = NSBezierPath()
            seam.move(to: point(9.0, 12.75, in: rect, scale: scale))
            seam.curve(
                to: point(9.0, 3.55, in: rect, scale: scale),
                controlPoint1: point(8.82, 10.1, in: rect, scale: scale),
                controlPoint2: point(9.18, 6.15, in: rect, scale: scale)
            )
            seam.lineWidth = 0.46 * scale
            seam.lineCapStyle = .round
            seam.stroke()
        }

        drawFold(
            topX: open ? 4.55 : 5.3,
            bottomX: open ? 4.02 : 4.25,
            in: rect,
            scale: scale,
            mirrored: false
        )
        drawFold(
            topX: open ? 4.55 : 5.3,
            bottomX: open ? 4.02 : 4.25,
            in: rect,
            scale: scale,
            mirrored: true
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func panelPath(in rect: NSRect,
                                  scale: CGFloat,
                                  open: Bool,
                                  mirrored: Bool) -> NSBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            point(mirrored ? 18 - x : x, y, in: rect, scale: scale)
        }

        let topOuter = 3.15
        let topInner = open ? 7.7 : 8.95
        let bottomInner = open ? 7.4 : 8.9
        let bottomOuter = 2.15

        let path = NSBezierPath()
        path.move(to: p(topOuter, 13.0))
        path.curve(
            to: p(topInner, 12.9),
            controlPoint1: p(4.4, 13.45),
            controlPoint2: p(6.2, 13.32)
        )
        path.curve(
            to: p(bottomInner, 3.35),
            controlPoint1: p(topInner + 0.5, 10.2),
            controlPoint2: p(bottomInner + 0.55, 6.2)
        )
        path.curve(
            to: p(bottomOuter, 3.15),
            controlPoint1: p(6.5, 2.55),
            controlPoint2: p(3.9, 2.6)
        )
        path.curve(
            to: p(topOuter, 13.0),
            controlPoint1: p(1.9, 8.3),
            controlPoint2: p(2.3, 11.2)
        )
        path.close()
        return path
    }

    private static func drawFold(topX: CGFloat,
                                 bottomX: CGFloat,
                                 in rect: NSRect,
                                 scale: CGFloat,
                                 mirrored: Bool) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            point(mirrored ? 18 - x : x, y, in: rect, scale: scale)
        }
        let fold = NSBezierPath()
        fold.move(to: p(topX, 12.45))
        fold.curve(
            to: p(bottomX, 4.12),
            controlPoint1: p(topX - 0.4, 9.35),
            controlPoint2: p(bottomX + 0.45, 6.75)
        )
        fold.lineWidth = 0.46 * scale
        fold.lineCapStyle = .round
        fold.stroke()
    }

    private static func drawLockBadge(in rect: NSRect) {
        let scale = rect.width / 18
        punchBadge(in: rect, scale: scale)
        NSColor.black.setFill()
        NSColor.black.setStroke()

        NSBezierPath(
            roundedRect: NSRect(
                x: rect.minX + 13.0 * scale,
                y: rect.minY + 1.65 * scale,
                width: 3.1 * scale,
                height: 2.45 * scale
            ),
            xRadius: 0.45 * scale,
            yRadius: 0.45 * scale
        ).fill()

        let shackle = NSBezierPath()
        shackle.move(to: NSPoint(
            x: rect.minX + 13.55 * scale,
            y: rect.minY + 4.0 * scale
        ))
        shackle.line(to: NSPoint(
            x: rect.minX + 13.55 * scale,
            y: rect.minY + 4.55 * scale
        ))
        shackle.curve(
            to: NSPoint(
                x: rect.minX + 15.55 * scale,
                y: rect.minY + 4.55 * scale
            ),
            controlPoint1: NSPoint(
                x: rect.minX + 13.55 * scale,
                y: rect.minY + 5.9 * scale
            ),
            controlPoint2: NSPoint(
                x: rect.minX + 15.55 * scale,
                y: rect.minY + 5.9 * scale
            )
        )
        shackle.line(to: NSPoint(
            x: rect.minX + 15.55 * scale,
            y: rect.minY + 4.0 * scale
        ))
        shackle.lineWidth = 0.82 * scale
        shackle.lineCapStyle = .round
        shackle.stroke()
    }

    private static func drawRecordingBadge(in rect: NSRect) {
        let scale = rect.width / 18
        punchBadge(in: rect, scale: scale)
        NSColor.black.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + 12.72 * scale,
                y: rect.minY + 1.52 * scale,
                width: 3.56 * scale,
                height: 3.56 * scale
            )
        ).fill()
    }

    private static func punchBadge(in rect: NSRect, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + 11.45 * scale,
                y: rect.minY + 0.25 * scale,
                width: 6.1 * scale,
                height: 6.1 * scale
            )
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func point(_ x: CGFloat,
                              _ y: CGFloat,
                              in rect: NSRect,
                              scale: CGFloat) -> NSPoint {
        NSPoint(
            x: rect.minX + x * scale,
            y: rect.minY + y * scale
        )
    }
}
