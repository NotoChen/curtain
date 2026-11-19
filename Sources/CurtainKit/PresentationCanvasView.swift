import AppKit

/// 展示模式的实际画布。窗口、设置预览和 DEBUG 预览共用同一套布局，
/// 避免预览与实际幕帘各维护一份时钟样式。
public final class PresentationCanvasView: NSView {
    private let background = AspectFillImageView()
    private let shade = PresentationShadeView()
    private let card = NSView()
    private let clockView: PresentationClockView
    private let sceneMessageLabel = NSTextField(labelWithString: "")
    private let returnLabel = NSTextField(labelWithString: "")
    private let returnHint = PresentationReturnHintView()
    private let compact: Bool
    private var hintWorkItem: DispatchWorkItem?
    private var hintAnimationToken = 0
    private var backgroundColor: CurtainColor

    public init(color: CurtainColor,
                image: CGImage? = nil,
                focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                zoom: CGFloat = 1,
                dim: CGFloat = 0,
                clockStyle: PresentationClockStyle,
                status: PresentationStatus?,
                compact: Bool = false) {
        self.backgroundColor = color
        self.compact = compact
        self.clockView = PresentationClockView(style: clockStyle, compact: compact)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = presentationNSColor(color).cgColor

        background.autoresizingMask = [.width, .height]
        background.apply(image: image, focus: focus, zoom: zoom)
        background.isHidden = image == nil
        addSubview(background)

        shade.autoresizingMask = [.width, .height]
        addSubview(shade)

        card.wantsLayer = true
        card.layer?.cornerRadius = compact ? 20 : 28
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        card.layer?.borderWidth = 0.8
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowRadius = compact ? 18 : 30
        card.layer?.shadowOffset = CGSize(width: 0, height: compact ? -6 : -10)
        card.layer?.shadowOpacity = 0.3
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        sceneMessageLabel.font = .systemFont(
            ofSize: compact ? 10 : 18,
            weight: .semibold
        )
        sceneMessageLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        sceneMessageLabel.alignment = .center
        sceneMessageLabel.maximumNumberOfLines = 2
        sceneMessageLabel.lineBreakMode = .byTruncatingTail

        returnLabel.font = .systemFont(
            ofSize: compact ? 8 : 12,
            weight: .regular
        )
        returnLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        returnLabel.alignment = .center
        returnLabel.maximumNumberOfLines = 1
        returnLabel.lineBreakMode = .byTruncatingTail

        clockView.translatesAutoresizingMaskIntoConstraints = false
        let cardStack = NSStackView(
            views: [sceneMessageLabel, clockView, returnLabel]
        )
        cardStack.orientation = .vertical
        cardStack.spacing = compact ? 6 : 10
        cardStack.alignment = .centerX
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        let horizontalPadding: CGFloat = compact ? 20 : 30
        let verticalPadding: CGFloat = compact ? 18 : 28
        let width = card.widthAnchor.constraint(
            equalToConstant: compact ? 360 : 580
        )
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            width,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            cardStack.leadingAnchor.constraint(
                equalTo: card.leadingAnchor,
                constant: horizontalPadding
            ),
            cardStack.trailingAnchor.constraint(
                equalTo: card.trailingAnchor,
                constant: -horizontalPadding
            ),
            cardStack.topAnchor.constraint(
                equalTo: card.topAnchor,
                constant: verticalPadding
            ),
            cardStack.bottomAnchor.constraint(
                equalTo: card.bottomAnchor,
                constant: -verticalPadding
            ),
        ])
        if let status {
            clockView.update(status: status)
        }

        returnHint.isHidden = true
        returnHint.alphaValue = 0
        returnHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(returnHint)
        let hintBottom = returnHint.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: compact ? -18 : -56
        )
        NSLayoutConstraint.activate([
            returnHint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintBottom,
            returnHint.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 24
            ),
            returnHint.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        background.frame = bounds
        shade.frame = bounds
    }

    public func update(status: PresentationStatus) {
        clockView.update(status: status)
        sceneMessageLabel.stringValue = status.messageText
        sceneMessageLabel.isHidden = status.messageText.isEmpty
        returnLabel.stringValue = status.returnText
        returnLabel.isHidden = status.returnText.isEmpty
    }

    public func setColor(_ color: CurtainColor) {
        backgroundColor = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = presentationNSColor(color).cgColor
        }
    }

    public func setBackgroundImage(_ image: CGImage?,
                                  focus: CGPoint,
                                  zoom: CGFloat,
                                  dim: CGFloat) {
        background.apply(image: image, focus: focus, zoom: zoom)
        background.isHidden = image == nil
        shade.dimOpacity = dim
        shade.needsDisplay = true
    }

    public func setClockStyle(_ style: PresentationClockStyle) {
        clockView.setStyle(style)
    }

    /// 回座提示只短暂出现，不承载统计或长期状态。
    public func showReturnHint(_ text: String, duration: TimeInterval = 7) {
        guard !compact else { return }
        returnHint.setText(text)
        hintWorkItem?.cancel()
        hintAnimationToken += 1
        let token = hintAnimationToken
        returnHint.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            returnHint.animator().alphaValue = 1
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hintAnimationToken == token else { return }
            self.hideReturnHint()
        }
        hintWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    public func hideReturnHint(animated: Bool = true) {
        hintWorkItem?.cancel()
        hintWorkItem = nil
        hintAnimationToken += 1
        let token = hintAnimationToken
        guard !returnHint.isHidden else { return }
        guard animated else {
            returnHint.alphaValue = 0
            returnHint.isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            returnHint.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.hintAnimationToken == token else { return }
            self.returnHint.isHidden = true
        }
    }
}

private final class PresentationReturnHintView: NSView {
    private let textLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        layer?.shadowOpacity = 0.28

        let keycap = PresentationKeycapView()
        textLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        textLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        textLabel.maximumNumberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [keycap, textLabel])
        row.orientation = .horizontal
        row.spacing = 9
        row.alignment = .centerY
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        textLabel.stringValue = text
    }
}

private final class PresentationKeycapView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: "esc")
        label.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.76)
        label.alignment = .center
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 20),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class PresentationShadeView: NSView {
    var dimOpacity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if dimOpacity > 0 {
            NSColor.black.withAlphaComponent(dimOpacity).setFill()
            bounds.fill()
        }
        let gradient = NSGradient(
            starting: NSColor.black.withAlphaComponent(0.08),
            ending: NSColor.black.withAlphaComponent(0.46)
        )
        gradient?.draw(in: bounds, angle: -90)
    }
}

func presentationNSColor(_ color: CurtainColor) -> NSColor {
    NSColor(
        srgbRed: CGFloat(color.red),
        green: CGFloat(color.green),
        blue: CGFloat(color.blue),
        alpha: 1
    )
}
