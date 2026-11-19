import AppKit
import CurtainKit

final class ClockStylePickerView: NSView {
    var onSelect: ((PresentationClockStyle) -> Void)?
    var selectedStyle: PresentationClockStyle = .digital {
        didSet { updateSelection() }
    }

    private let tiles: [ClockStyleTileView]

    override init(frame frameRect: NSRect) {
        tiles = PresentationClockStyle.allCases.map {
            ClockStyleTileView(style: $0)
        }
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: tiles)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 70),
        ])
        for tile in tiles {
            tile.onClick = { [weak self, weak tile] in
                guard let self, let tile else { return }
                self.selectedStyle = tile.style
                self.onSelect?(tile.style)
            }
        }
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateSelection() {
        for tile in tiles {
            tile.setSelected(tile.style == selectedStyle)
        }
    }
}

private final class ClockStyleTileView: NSView {
    let style: PresentationClockStyle
    var onClick: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let glyph: ClockStyleGlyphView
    private var selected = false

    init(style: PresentationClockStyle) {
        self.style = style
        self.glyph = ClockStyleGlyphView(style: style)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.8

        titleLabel.stringValue = style.displayName
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = CurtainTheme.ink
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(glyph)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            glyph.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            glyph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            glyph.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(style.displayName)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func setSelected(_ selected: Bool) {
        guard self.selected != selected else { return }
        self.selected = selected
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = selected
                ? CurtainTheme.accent.withAlphaComponent(0.13).cgColor
                : CurtainTheme.field.cgColor
            layer?.borderColor = selected
                ? CurtainTheme.accent.withAlphaComponent(0.58).cgColor
                : CurtainTheme.border.cgColor
            titleLabel.textColor = selected ? CurtainTheme.accent : CurtainTheme.secondaryInk
        }
    }
}

private final class ClockStyleGlyphView: NSView {
    private let style: PresentationClockStyle

    init(style: PresentationClockStyle) {
        self.style = style
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: 8,
            yRadius: 8
        ).fill()
        switch style {
        case .digital:
            drawDigital()
        case .analog:
            drawAnalog()
        case .editorial:
            drawEditorial()
        }
    }

    private func drawDigital() {
        let time = NSAttributedString(
            string: "14:32",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .ultraLight),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
        )
        let seconds = NSAttributedString(
            string: ":05",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.46),
            ]
        )
        let timeSize = time.size()
        let secondsSize = seconds.size()
        let total = timeSize.width + 3 + secondsSize.width
        let x = bounds.midX - total / 2
        time.draw(at: NSPoint(x: x, y: bounds.midY - timeSize.height / 2))
        seconds.draw(at: NSPoint(
            x: x + timeSize.width + 3,
            y: bounds.midY - secondsSize.height / 2
        ))
    }

    private func drawAnalog() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.42
        NSColor.white.withAlphaComponent(0.24).setStroke()
        let ring = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        ring.lineWidth = 1
        ring.stroke()

        drawHand(angle: -.pi / 2 + .pi / 3, length: radius * 0.5, width: 2)
        drawHand(angle: -.pi / 2 + .pi * 0.7, length: radius * 0.7, width: 1.4)
        CurtainTheme.accent.setStroke()
        let second = NSBezierPath()
        second.move(to: center)
        second.line(to: CGPoint(
            x: center.x + cos(-.pi / 2 + .pi * 1.2) * radius * 0.75,
            y: center.y + sin(-.pi / 2 + .pi * 1.2) * radius * 0.75
        ))
        second.lineWidth = 0.8
        second.stroke()
    }

    private func drawHand(angle: CGFloat, length: CGFloat, width: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        NSColor.white.withAlphaComponent(0.82).setStroke()
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: CGPoint(
            x: center.x + cos(angle) * length,
            y: center.y + sin(angle) * length
        ))
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawEditorial() {
        let day = NSAttributedString(
            string: "17",
            attributes: [
                .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
        )
        let meta = NSAttributedString(
            string: "11月 · 星期二",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: CurtainTheme.accent.withAlphaComponent(0.92),
            ]
        )
        let daySize = day.size()
        let metaSize = meta.size()
        day.draw(at: NSPoint(x: bounds.midX - daySize.width / 2, y: bounds.midY - 2))
        meta.draw(at: NSPoint(x: bounds.midX - metaSize.width / 2, y: 1))
    }
}
