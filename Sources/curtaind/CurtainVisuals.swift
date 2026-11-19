import AppKit
import CurtainKit
import ImageIO

enum CurtainTheme {
    static let accent = NSColor(srgbRed: 0.86, green: 0.65, blue: 0.29, alpha: 1)
    static let accentStrong = NSColor(srgbRed: 0.96, green: 0.75, blue: 0.36, alpha: 1)
    static let success = NSColor(srgbRed: 0.29, green: 0.79, blue: 0.53, alpha: 1)
    static let warning = NSColor(srgbRed: 0.96, green: 0.66, blue: 0.25, alpha: 1)
    static let danger = NSColor(srgbRed: 0.94, green: 0.35, blue: 0.36, alpha: 1)
    static let focus = NSColor(srgbRed: 0.44, green: 0.66, blue: 0.96, alpha: 1)
    static let ink = NSColor.labelColor
    static let secondaryInk = NSColor.secondaryLabelColor
    static let tertiaryInk = NSColor.tertiaryLabelColor
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 18
    static let windowInset: CGFloat = 32

    static let card = dynamic(
        light: NSColor(white: 1, alpha: 0.64),
        dark: NSColor(white: 1, alpha: 0.055)
    )
    static let field = dynamic(
        light: NSColor(white: 1, alpha: 0.7),
        dark: NSColor(white: 1, alpha: 0.045)
    )
    static let border = dynamic(
        light: NSColor.black.withAlphaComponent(0.085),
        dark: NSColor.white.withAlphaComponent(0.1)
    )
    static let sidebar = dynamic(
        light: NSColor(white: 0.94, alpha: 0.58),
        dark: NSColor(white: 0.035, alpha: 0.46)
    )
    static let buttonText = NSColor(srgbRed: 0.12, green: 0.1, blue: 0.07, alpha: 0.92)

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }

    static func label(_ text: String,
                      size: CGFloat,
                      weight: NSFont.Weight = .regular,
                      color: NSColor = ink) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    static func monoLabel(_ text: String,
                          size: CGFloat,
                          weight: NSFont.Weight = .regular,
                          color: NSColor = ink) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    static func stack(_ views: [NSView],
                      orientation: NSUserInterfaceLayoutOrientation = .vertical,
                      spacing: CGFloat = 0,
                      alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.spacing = spacing
        stack.alignment = alignment
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}

enum CurtainAppIcon {
    static func bundled(pointSize: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ) else { return nil }
        return image(at: url, pointSize: pointSize)
    }

    static func image(at url: URL, pointSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: pointSize, height: pointSize)
        )
    }
}

final class CurtainBackdropView: NSView {
    private let effect = NSVisualEffectView()
    private let tint = CurtainBackdropTintView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        addSubview(effect)
        addSubview(tint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effect.frame = bounds
        tint.frame = bounds
    }
}

private final class CurtainBackdropTintView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let colors: [NSColor] = dark
                ? [
                    NSColor(srgbRed: 0.07, green: 0.082, blue: 0.105, alpha: 0.78),
                    NSColor(srgbRed: 0.024, green: 0.03, blue: 0.041, alpha: 0.94),
                ]
                : [
                    NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 0.74),
                    NSColor(srgbRed: 0.9, green: 0.89, blue: 0.86, alpha: 0.84),
                ]
            NSGradient(colors: colors)?.draw(in: bounds, angle: -35)
        }
    }
}

final class CurtainCardView: NSView {
    let contentView = NSView()

    init(
        padding: NSEdgeInsets = NSEdgeInsets(
            top: CurtainTheme.cardPadding,
            left: CurtainTheme.cardPadding,
            bottom: CurtainTheme.cardPadding,
            right: CurtainTheme.cardPadding
        )
    ) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = false
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowOpacity = 0.16
        layer?.shadowColor = NSColor.black.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: padding.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.bottom),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CurtainTheme.card.cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = CurtainTheme.border.cgColor
        }
    }
}

final class CurtainDividerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CurtainTheme.border.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
        }
    }
}

final class CurtainStatusPillView: NSView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var color: NSColor

    init(text: String, color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.maximumNumberOfLines = 1
        addSubview(dot)
        addSubview(label)
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update(text: text, color: color)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(text: String, color: NSColor) {
        self.color = color
        label.stringValue = text
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label.textColor = color
            dot.layer?.backgroundColor = color.cgColor
            layer?.backgroundColor = color.withAlphaComponent(0.11).cgColor
            layer?.borderWidth = 0.6
            layer?.borderColor = color.withAlphaComponent(0.18).cgColor
        }
        invalidateIntrinsicContentSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        update(text: label.stringValue, color: color)
    }
}

final class CurtainButton: NSButton {
    enum Style: Equatable {
        case primary
        case secondary
        case danger
        case quiet

        var height: CGFloat {
            switch self {
            case .primary: return 38
            case .secondary, .danger, .quiet: return 34
            }
        }

        var horizontalPadding: CGFloat {
            self == .primary ? 20 : 16
        }
    }

    private var titleText: String
    private let style: Style
    private var symbol: String?
    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    init(title: String,
         symbol: String? = nil,
         style: Style,
         target: AnyObject?,
         action: Selector?) {
        self.titleText = title
        self.style = style
        self.symbol = symbol
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.7
        font = .systemFont(ofSize: style == .primary ? 13 : 12, weight: .medium)
        if let symbol {
            image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: title
            )
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            imageHugsTitle = true
            imageScaling = .scaleProportionallyDown
        }
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: style.height).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(
            width: max(style.height, base.width + style.horizontalPadding * 2),
            height: style.height
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func highlight(_ flag: Bool) {
        alphaValue = flag ? 0.76 : 1
    }

    func setTitle(_ title: String) {
        titleText = title
        updateAppearance()
        invalidateIntrinsicContentSize()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let foreground: NSColor
            switch style {
            case .primary:
                foreground = CurtainTheme.buttonText
                layer?.backgroundColor = CurtainTheme.accent.cgColor
                layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            case .secondary:
                foreground = CurtainTheme.ink
                layer?.backgroundColor = CurtainTheme.field.cgColor
                layer?.borderColor = CurtainTheme.border.cgColor
            case .danger:
                foreground = CurtainTheme.danger
                layer?.backgroundColor = CurtainTheme.danger.withAlphaComponent(0.12).cgColor
                layer?.borderColor = CurtainTheme.danger.withAlphaComponent(0.24).cgColor
            case .quiet:
                foreground = CurtainTheme.secondaryInk
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderColor = NSColor.clear.cgColor
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attributedTitle = NSAttributedString(
                string: titleText,
                attributes: [
                    .font: font ?? NSFont.systemFont(ofSize: 12),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph,
                ]
            )
            contentTintColor = foreground
        }
    }
}

final class CurtainIconButton: NSButton {
    init(symbol: String,
         accessibilityLabel: String,
         target: AnyObject?,
         action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 9
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityLabel
        )
        imageScaling = .scaleProportionallyDown
        imagePosition = .imageOnly
        contentTintColor = CurtainTheme.secondaryInk
        setAccessibilityLabel(accessibilityLabel)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func highlight(_ flag: Bool) {
        alphaValue = flag ? 0.68 : 1
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        }
    }
}

final class CurtainNavRow: NSView {
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { updateAppearance() }
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private var hovered = false

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        iconView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )
        iconView.imageScaling = .scaleProportionallyDown
        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        addSubview(iconView)
        addSubview(label)
        addSubview(dot)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 5),
            dot.heightAnchor.constraint(equalToConstant: 5),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.68
        onClick?()
        alphaValue = 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let foreground = isSelected ? CurtainTheme.ink : CurtainTheme.secondaryInk
            label.textColor = foreground
            iconView.contentTintColor = isSelected ? CurtainTheme.accent : CurtainTheme.secondaryInk
            setAccessibilitySelected(isSelected)
            dot.layer?.backgroundColor = CurtainTheme.accent.cgColor
            dot.isHidden = !isSelected
            if isSelected {
                layer?.backgroundColor = CurtainTheme.accent.withAlphaComponent(0.12).cgColor
            } else if hovered {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
}

final class CurtainIconTile: NSView {
    private let iconView = NSImageView()
    private var color: NSColor

    init(symbol: String, color: NSColor, size: CGFloat = 38) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size * 0.28
        let configuration = NSImage.SymbolConfiguration(
            pointSize: size * 0.44,
            weight: .medium
        )
        iconView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: size * 0.5),
            iconView.heightAnchor.constraint(equalToConstant: size * 0.5),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: NSColor) {
        self.color = color
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.withAlphaComponent(0.11).cgColor
            iconView.contentTintColor = color
        }
    }
}

final class CurtainNumberField: NSView, NSTextFieldDelegate {
    private let textField = NSTextField()
    private let suffixLabel = NSTextField(labelWithString: "")
    private let allowedRange: ClosedRange<Double>
    private let decimalPlaces: Int
    var onChange: (() -> Void)?
    var isEnabled = true {
        didSet {
            textField.isEnabled = isEnabled
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    var value: Double {
        get {
            guard let parsed = parsedValue else { return fallbackValue }
            return clamped(parsed)
        }
        set {
            fallbackValue = clamped(newValue)
            textField.stringValue = formatted(fallbackValue)
            inputIsValid = true
            updateAppearance()
        }
    }

    var isValid: Bool {
        guard let parsed = parsedValue else { return false }
        return allowedRange.contains(parsed)
    }

    private var fallbackValue: Double
    private var inputIsValid = true

    init(value: Double,
         suffix: String,
         range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude,
         decimalPlaces: Int = 1) {
        self.allowedRange = range
        self.decimalPlaces = max(0, decimalPlaces)
        self.fallbackValue = min(range.upperBound, max(range.lowerBound, value))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        textField.stringValue = formatted(fallbackValue)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        textField.alignment = .right
        textField.textColor = CurtainTheme.ink
        textField.delegate = self
        suffixLabel.stringValue = suffix
        toolTip = "\(formatted(allowedRange.lowerBound))–\(formatted(allowedRange.upperBound))\(suffix)"
        suffixLabel.font = .systemFont(ofSize: 10.5)
        suffixLabel.textColor = CurtainTheme.secondaryInk
        addSubview(textField)
        addSubview(suffixLabel)
        textField.translatesAutoresizingMaskIntoConstraints = false
        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 108),
            heightAnchor.constraint(equalToConstant: 32),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 48),
            suffixLabel.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 5),
            suffixLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            suffixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func controlTextDidChange(_ notification: Notification) {
        inputIsValid = isValid
        updateAppearance()
        onChange?()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if let parsed = parsedValue {
            fallbackValue = clamped(parsed)
        }
        textField.stringValue = formatted(fallbackValue)
        inputIsValid = true
        updateAppearance()
        onChange?()
    }

    private var parsedValue: Double? {
        let raw = textField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    private func clamped(_ value: Double) -> Double {
        min(allowedRange.upperBound, max(allowedRange.lowerBound, value))
    }

    private func formatted(_ value: Double) -> String {
        String(format: decimalPlaces == 0 ? "%.0f" : "%.1f", value)
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CurtainTheme.field.cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = (inputIsValid
                ? CurtainTheme.border
                : CurtainTheme.danger
            ).cgColor
        }
    }
}

final class CurtainSettingRow: NSView {
    init(title: String,
         detail: String? = nil,
         control: NSView,
         verticalInset: CGFloat = 10) {
        super.init(frame: .zero)
        let titleLabel = CurtainTheme.label(title, size: 12.5, weight: .medium)
        var textViews: [NSView] = [titleLabel]
        if let detail, !detail.isEmpty {
            let detailLabel = CurtainTheme.label(
                detail,
                size: 10.5,
                color: CurtainTheme.secondaryInk
            )
            detailLabel.maximumNumberOfLines = 2
            textViews.append(detailLabel)
        }
        let textStack = CurtainTheme.stack(textViews, spacing: 3)
        let row = CurtainTheme.stack(
            [textStack, control],
            orientation: .horizontal,
            spacing: 18,
            alignment: .centerY
        )
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalInset),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class CurtainBrandIconView: NSView {
    private let imageView = NSImageView()
    private let gradient = CAGradientLayer()

    init(size: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size * 0.23
        layer?.masksToBounds = true
        layer?.borderWidth = 0.7
        gradient.colors = [
            NSColor(srgbRed: 0.15, green: 0.18, blue: 0.22, alpha: 1).cgColor,
            NSColor(srgbRed: 0.025, green: 0.032, blue: 0.043, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.1, y: 1)
        gradient.endPoint = CGPoint(x: 0.9, y: 0)
        layer?.addSublayer(gradient)
        if let icon = CurtainAppIcon.bundled(pointSize: size) {
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            gradient.isHidden = true
        } else {
            imageView.image = CurtainGlyph.brandImage(size: size)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.contentTintColor = NSColor(
                srgbRed: 0.94,
                green: 0.88,
                blue: 0.76,
                alpha: 1
            )
        }
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }
}

enum CurtainWindowChrome {
    static func apply(to window: NSWindow, title: String) {
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    /// 在鼠标所在屏幕居中，避免双屏时设置/报告总跑到主屏。
    static func centerOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let margin: CGFloat = 24
        let maxSize = NSSize(
            width: max(640, visible.width - margin * 2),
            height: max(520, visible.height - margin * 2)
        )
        let current = window.frame.size
        let size = NSSize(
            width: min(current.width, maxSize.width),
            height: min(current.height, maxSize.height)
        )
        window.minSize = NSSize(
            width: min(window.minSize.width, size.width),
            height: min(window.minSize.height, size.height)
        )
        var frame = window.frame
        frame.size = size
        frame.origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        if frame != window.frame {
            window.setFrame(frame, display: false)
        }
    }
}
