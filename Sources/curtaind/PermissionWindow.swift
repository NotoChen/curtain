import AppKit
import CurtainKit

/// 首次运行 / 权限缺失时的引导面板。
/// 每行一个权限：状态灯 + 说明 + 「打开设置」直达对应系统面板；
/// 授权后状态灯会自动变绿（1 秒轮询），不需要重启面板。
final class PermissionWindowController: NSWindowController {
    var onAllGranted: (() -> Void)?

    private var statusDots: [String: NSTextField] = [:]
    private var statusTexts: [String: NSTextField] = [:]
    private var timer: Timer?
    private var footer: NSTextField?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Curtain 需要两项系统权限"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "幕帘需要两项权限才能工作")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "点右侧按钮会直接打开系统设置里对应的面板。macOS 26 起「辅助功能」并入了「设备控制和数据访问」，勾选 Curtain.app 即可；列表里没有它时，点面板下方的 + 选择 /Applications/Curtain.app。勾上后这里会自动变绿。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 3
        subtitle.preferredMaxLayoutWidth = 470
        stack.addArrangedSubview(subtitle)

        stack.addArrangedSubview(makeRow(
            key: "ax",
            title: "设备控制和数据访问（原「辅助功能」）",
            detail: "拦截键盘鼠标（防误触）、长按 Esc 触发 Touch ID。macOS 26 起这个面板同时管录屏与控制权限。",
            action: #selector(openAccessibility)
        ))

        stack.addArrangedSubview(makeRow(
            key: "screen",
            title: "屏幕录制",
            detail: "截取完整桌面、录制屏幕；画面里不会包含幕帘本身。",
            action: #selector(openScreenRecording)
        ))

        let footerLabel = NSTextField(labelWithString: "")
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.textColor = .secondaryLabelColor
        footer = footerLabel
        stack.addArrangedSubview(footerLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let refreshButton = NSButton(title: "重新检测", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        buttons.addArrangedSubview(refreshButton)

        let closeButton = NSButton(title: "稍后", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded
        buttons.addArrangedSubview(closeButton)

        stack.addArrangedSubview(buttons)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        window.contentView = container
    }

    private func makeRow(key: String, title: String, detail: String, action: Selector) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let dot = NSTextField(labelWithString: "○")
        dot.font = .systemFont(ofSize: 16, weight: .bold)
        dot.textColor = .systemRed
        dot.setContentHuggingPriority(.required, for: .horizontal)
        statusDots[key] = dot

        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.preferredMaxLayoutWidth = 300

        let status = NSTextField(labelWithString: "未授权")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .systemRed
        statusTexts[key] = status

        texts.addArrangedSubview(titleLabel)
        texts.addArrangedSubview(detailLabel)
        texts.addArrangedSubview(status)
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let button = NSButton(title: "打开设置", target: self, action: action)
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(dot)
        row.addArrangedSubview(texts)
        row.addArrangedSubview(button)
        return row
    }

    // MARK: - 状态刷新

    @objc private func refreshClicked() {
        refresh()
    }

    @objc private func closeClicked() {
        stopPolling()
        window?.orderOut(nil)
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
        startPolling()
    }

    @objc private func openScreenRecording() {
        Permissions.openScreenRecordingSettings()
        startPolling()
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let ax = Permissions.hasAccessibility()
        let screen = Permissions.hasScreenRecording()
        apply(key: "ax", granted: ax)
        apply(key: "screen", granted: screen)

        if ax && screen {
            footer?.stringValue = "两项权限都已就绪。"
            footer?.textColor = .systemGreen
            stopPolling()
            onAllGranted?()
        } else if ax {
            footer?.stringValue = "辅助功能已就绪；还差屏幕录制（截图/录屏要用）。"
            footer?.textColor = .secondaryLabelColor
        } else {
            footer?.stringValue = "提示：授权后若仍提示未授权，请退出并重新打开 Curtain。"
            footer?.textColor = .secondaryLabelColor
        }
    }

    private func apply(key: String, granted: Bool) {
        statusDots[key]?.stringValue = granted ? "●" : "○"
        statusDots[key]?.textColor = granted ? .systemGreen : .systemRed
        statusTexts[key]?.stringValue = granted ? "已授权" : "未授权"
        statusTexts[key]?.textColor = granted ? .systemGreen : .systemRed
    }
}
