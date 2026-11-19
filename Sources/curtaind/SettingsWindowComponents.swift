import AppKit
import CurtainKit

enum SettingsPage: CaseIterable {
    case general
    case automation
    case scenes
    case presentation
    case permissions
    case diagnostics

    var title: String {
        switch self {
        case .general: return "幕帘"
        case .automation: return "自动化"
        case .scenes: return "场景"
        case .presentation: return "展示模式"
        case .permissions: return "权限"
        case .diagnostics: return "诊断"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "设置幕帘的解锁动作、快捷键和物理输入行为。"
        case .automation:
            return "空闲起幕、每日保护时段和合盖运行。"
        case .scenes:
            return "为离开、会议、访客和专注分别配置快捷键、时长、背景与提示。"
        case .presentation:
            return "自定义背景、日期、时间、星期、农历和三种时钟样式。"
        case .permissions:
            return "打开系统设置完成两项授权；重装后授权失效也在这里修复。"
        case .diagnostics:
            return "检查当前环境，打开配置、审计日志和诊断信息。"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "rectangle.inset.filled"
        case .automation: return "clock.badge.checkmark"
        case .scenes: return "rectangle.3.group"
        case .presentation: return "photo.on.rectangle.angled"
        case .permissions: return "checkmark.shield"
        case .diagnostics: return "stethoscope"
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class PermissionStateRowView: NSView {
    private let tile: CurtainIconTile
    private let pill: CurtainStatusPillView
    private let detail: NSTextField

    init(symbol: String, title: String, detail: String, granted: Bool) {
        tile = CurtainIconTile(
            symbol: symbol,
            color: granted ? CurtainTheme.success : CurtainTheme.warning,
            size: 38
        )
        pill = CurtainStatusPillView(
            text: granted ? "已授权" : "未授权",
            color: granted ? CurtainTheme.success : CurtainTheme.warning
        )
        self.detail = CurtainTheme.label(
            detail,
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        super.init(frame: .zero)
        let titleLabel = CurtainTheme.label(title, size: 12.5, weight: .semibold)
        let textStack = CurtainTheme.stack([titleLabel, self.detail], spacing: 3)
        let row = CurtainTheme.stack(
            [tile, textStack, pill],
            orientation: .horizontal,
            spacing: 14,
            alignment: .centerY
        )
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pill.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setGranted(_ granted: Bool) {
        tile.setColor(granted ? CurtainTheme.success : CurtainTheme.warning)
        pill.update(
            text: granted ? "已授权" : "未授权",
            color: granted ? CurtainTheme.success : CurtainTheme.warning
        )
    }
}

final class CurtainPresentationPreviewView: NSView {
    private let canvas: PresentationCanvasView
    private let blackoutLabel = NSTextField(labelWithString: "纯黑幕帘")
    private var loadedImagePath: String?
    private var loadedImage: CGImage?

    override init(frame frameRect: NSRect) {
        canvas = PresentationCanvasView(
            color: .black,
            image: nil,
            clockStyle: .digital,
            status: nil,
            compact: true
        )
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        blackoutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        blackoutLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        blackoutLabel.alignment = .center
        blackoutLabel.isHidden = true
        addSubview(blackoutLabel)
        blackoutLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blackoutLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            blackoutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(color: NSColor,
                imagePath: String?,
                clockStyle: PresentationClockStyle,
                imageFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                imageZoom: CGFloat = 1,
                imageDim: CGFloat = 0,
                startedAt: Date?,
                messageText: String = "",
                returnText: String = "",
                displayEnabled: Bool = true) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        let curtainColor = CurtainColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
        canvas.setColor(curtainColor)
        if loadedImagePath != imagePath {
            loadedImagePath = imagePath
            loadedImage = imagePath.flatMap {
                PresentationBackgroundLoader.load(path: $0, maxPixelSize: 1024)
            }
        }
        canvas.setBackgroundImage(
            loadedImage,
            focus: imageFocus,
            zoom: imageZoom,
            dim: imageDim
        )
        canvas.setClockStyle(clockStyle)
        canvas.isHidden = !displayEnabled
        blackoutLabel.isHidden = displayEnabled
        canvas.update(
            status: PresentationClockFormatter.status(
                at: Date(),
                startedAt: startedAt,
                messageText: messageText,
                returnText: returnText
            )
        )
    }
}

final class CurtainSliderField: NSView {
    var onChange: (() -> Void)?
    var isEnabled = true {
        didSet {
            slider.isEnabled = isEnabled
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let formatter: (Double) -> String

    var value: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = min(slider.maxValue, max(slider.minValue, newValue))
            updateLabel()
        }
    }

    init(minimum: Double,
         maximum: Double,
         value: Double,
         width: CGFloat = 230,
         sliderWidth: CGFloat = 168,
         formatter: @escaping (Double) -> String) {
        slider = NSSlider(
            value: min(maximum, max(minimum, value)),
            minValue: minimum,
            maxValue: maximum,
            target: nil,
            action: nil
        )
        self.formatter = formatter
        super.init(frame: .zero)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        valueLabel.textColor = CurtainTheme.secondaryInk
        valueLabel.alignment = .right
        addSubview(slider)
        addSubview(valueLabel)
        slider.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 30),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.widthAnchor.constraint(equalToConstant: sliderWidth),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() {
        updateLabel()
        onChange?()
    }

    private func updateLabel() {
        valueLabel.stringValue = formatter(slider.doubleValue)
    }
}
