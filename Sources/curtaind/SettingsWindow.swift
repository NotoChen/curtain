import AppKit
import CurtainKit

/// 设置窗口：只放用户真的会调的东西。
/// 幕帘行为（长按阈值、隐藏光标）+ 权限状态 + 诊断入口。
/// 截图目录、码率、白名单这些不属于用户设置，一律不进这个窗口。
final class SettingsWindowController: NSWindowController {
    var onSave: ((CurtainConfig) -> Void)?

    private var config: CurtainConfig
    private let holdField = NSTextField(string: "")
    private let hideCursorSwitch = NSButton(checkboxWithTitle: "幕帘期间隐藏鼠标指针", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")

    init(config: CurtainConfig) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Curtain 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
        loadValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshPermissions()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)

        content.addArrangedSubview(sectionTitle("幕帘"))

        holdField.alignment = .right
        holdField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        holdField.placeholderString = "2.0"
        content.addArrangedSubview(row("长按 Esc 解除：", control: holdField, suffix: "秒（1–5）"))

        hideCursorSwitch.target = self
        content.addArrangedSubview(indented(hideCursorSwitch))

        content.addArrangedSubview(separator())
        content.addArrangedSubview(sectionTitle("权限"))

        permissionLabel.font = .systemFont(ofSize: 12)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 2
        permissionLabel.lineBreakMode = .byWordWrapping
        content.addArrangedSubview(indented(permissionLabel))

        let permissionButtons = NSStackView()
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 12
        let openAX = NSButton(title: "设备控制和数据访问", target: self, action: #selector(openAccessibility))
        openAX.bezelStyle = .rounded
        let openSC = NSButton(title: "录屏与系统录音", target: self, action: #selector(openScreenRecording))
        openSC.bezelStyle = .rounded
        permissionButtons.addArrangedSubview(openAX)
        permissionButtons.addArrangedSubview(openSC)
        content.addArrangedSubview(indented(permissionButtons))

        content.addArrangedSubview(separator())
        content.addArrangedSubview(sectionTitle("诊断"))

        let diagnostics = NSStackView()
        diagnostics.orientation = .horizontal
        diagnostics.spacing = 12
        let copyDoctor = NSButton(title: "复制诊断信息", target: self, action: #selector(copyDiagnostics))
        copyDoctor.bezelStyle = .rounded
        let openAudit = NSButton(title: "打开审计日志", target: self, action: #selector(openAuditLog))
        openAudit.bezelStyle = .rounded
        let openConfig = NSButton(title: "打开配置文件", target: self, action: #selector(openConfigFile))
        openConfig.bezelStyle = .rounded
        diagnostics.addArrangedSubview(copyDoctor)
        diagnostics.addArrangedSubview(openAudit)
        diagnostics.addArrangedSubview(openConfig)
        content.addArrangedSubview(indented(diagnostics))

        content.addArrangedSubview(separator())

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.widthAnchor.constraint(equalToConstant: 476).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        actions.addArrangedSubview(cancel)
        actions.addArrangedSubview(save)
        content.addArrangedSubview(actions)

        let container = NSView()
        container.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        window.contentView = container
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func row(_ title: String, control: NSView, suffix: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 118).isActive = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(control)

        if !suffix.isEmpty {
            let suffixLabel = NSTextField(labelWithString: suffix)
            suffixLabel.textColor = .secondaryLabelColor
            suffixLabel.font = .systemFont(ofSize: 11)
            stack.addArrangedSubview(suffixLabel)
        }
        return stack
    }

    private func indented(_ view: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 118).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(view)
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return line
    }

    // MARK: - 值

    private func loadValues() {
        holdField.stringValue = String(format: "%.1f", config.holdToAuthSeconds)
        hideCursorSwitch.state = config.hideCursorDuringCurtain ? .on : .off
        refreshPermissions()
    }

    func refreshPermissions() {
        let ax = Permissions.hasAccessibility() ? "已授权" : "未授权"
        let screen = Permissions.hasScreenRecording() ? "已授权" : "未授权"
        permissionLabel.stringValue = "设备控制和数据访问：\(ax)\n录屏与系统录音：\(screen)"
    }

    // MARK: - 动作

    @objc private func openAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecording() {
        _ = Permissions.promptScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    @objc private func copyDiagnostics() {
        let lines = [
            "accessibility: \(Permissions.hasAccessibility() ? "granted" : "missing")",
            "screen_recording: \(Permissions.hasScreenRecording() ? "granted" : "missing")",
            "displays: \(NSScreen.screens.count)",
            "hold_to_auth: \(config.holdToAuthSeconds)",
            "hide_cursor: \(config.hideCursorDuringCurtain)",
            "version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
            "config: \(Paths.configURL.path)",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func openAuditLog() {
        NSWorkspace.shared.open(Paths.auditURL)
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(Paths.configURL)
    }

    @objc private func saveClicked() {
        var updated = config
        updated.holdToAuthSeconds = min(5.0, max(1.0, Double(holdField.stringValue) ?? 2.0))
        updated.hideCursorDuringCurtain = hideCursorSwitch.state == .on

        config = updated
        updated.save()
        onSave?(updated)
        window?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        loadValues()
        window?.orderOut(nil)
    }
}
