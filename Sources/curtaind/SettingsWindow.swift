import AppKit
import CurtainKit
import UniformTypeIdentifiers

/// 设置窗口：常规 / 采集 / 白名单 / 权限 四块。
/// 所有改动先落在窗口内的副本上，点「保存」才写回配置文件并通知 daemon 生效。
final class SettingsWindowController: NSWindowController {
    var onSave: ((CurtainConfig) -> Void)?

    private var config: CurtainConfig
    private var allowlist: [String]

    private let holdField = NSTextField(string: "")
    private let hideCursorSwitch = NSButton(checkboxWithTitle: "幕帘期间隐藏鼠标指针", target: nil, action: nil)
    private let captureDirField = NSTextField(string: "")
    private let captureCursorSwitch = NSButton(checkboxWithTitle: "截图默认包含鼠标指针", target: nil, action: nil)
    private let fpsField = NSTextField(string: "")
    private let bitrateField = NSTextField(string: "")
    private let allowStack = NSStackView()
    private let permissionLabel = NSTextField(labelWithString: "")

    init(config: CurtainConfig) {
        self.config = config
        self.allowlist = config.allowlist

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 660),
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

        content.addArrangedSubview(sectionTitle("常规"))

        holdField.alignment = .right
        holdField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        content.addArrangedSubview(row("长按 Esc 解除：", control: holdField, suffix: "秒（1–5）"))

        hideCursorSwitch.target = self
        content.addArrangedSubview(indented(hideCursorSwitch))

        content.addArrangedSubview(separator())
        content.addArrangedSubview(sectionTitle("采集"))

        captureDirField.widthAnchor.constraint(equalToConstant: 330).isActive = true
        captureDirField.placeholderString = "留空 = Application Support 目录"
        content.addArrangedSubview(row("默认截图目录：", control: captureDirField, suffix: "", button: ("选择…", #selector(pickDirectory))))

        captureCursorSwitch.target = self
        content.addArrangedSubview(indented(captureCursorSwitch))

        fpsField.alignment = .right
        fpsField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        content.addArrangedSubview(row("录屏帧率：", control: fpsField, suffix: "fps（1–60）"))

        bitrateField.alignment = .right
        bitrateField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        content.addArrangedSubview(row("录屏码率：", control: bitrateField, suffix: "bps（0 = 自动）"))

        content.addArrangedSubview(separator())
        content.addArrangedSubview(sectionTitle("白名单（幕帘期间可注入输入的进程）"))

        allowStack.orientation = .vertical
        allowStack.alignment = .leading
        allowStack.spacing = 4
        content.addArrangedSubview(indented(allowStack))

        let addButton = NSButton(title: "添加…", target: self, action: #selector(addAllowEntry))
        addButton.bezelStyle = .rounded
        content.addArrangedSubview(indented(addButton))

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

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10
        let save = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let copyDoctor = NSButton(title: "复制诊断信息", target: self, action: #selector(copyDiagnostics))
        copyDoctor.bezelStyle = .rounded
        let openAudit = NSButton(title: "打开审计日志", target: self, action: #selector(openAuditLog))
        openAudit.bezelStyle = .rounded
        actions.addArrangedSubview(save)
        actions.addArrangedSubview(cancel)
        actions.addArrangedSubview(copyDoctor)
        actions.addArrangedSubview(openAudit)
        content.addArrangedSubview(actions)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: 620),
        ])
        scroll.documentView = document

        let container = NSView()
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func row(_ title: String, control: NSView, suffix: String, button: (String, Selector)? = nil) -> NSView {
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
        if let (title, action) = button {
            let btn = NSButton(title: title, target: self, action: action)
            btn.bezelStyle = .rounded
            stack.addArrangedSubview(btn)
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
        line.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return line
    }

    // MARK: - 值

    private func loadValues() {
        holdField.stringValue = String(format: "%.1f", config.holdToAuthSeconds)
        hideCursorSwitch.state = config.hideCursorDuringCurtain ? .on : .off
        captureDirField.stringValue = config.captureDirectory
        captureCursorSwitch.state = config.captureCursor ? .on : .off
        fpsField.stringValue = "\(config.recordingFPS)"
        bitrateField.stringValue = "\(config.recordingBitrate)"
        rebuildAllowRows()
        refreshPermissions()
    }

    private func rebuildAllowRows() {
        for view in allowStack.arrangedSubviews {
            allowStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if allowlist.isEmpty {
            let empty = NSTextField(labelWithString: "（空：幕帘期间任何进程都无法注入输入）")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 11)
            allowStack.addArrangedSubview(empty)
            return
        }
        for (index, entry) in allowlist.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let label = NSTextField(labelWithString: entry)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
            label.widthAnchor.constraint(equalToConstant: 430).isActive = true
            let remove = NSButton(title: "移除", target: self, action: #selector(removeAllowEntry(_:)))
            remove.bezelStyle = .rounded
            remove.tag = index
            row.addArrangedSubview(label)
            row.addArrangedSubview(remove)
            allowStack.addArrangedSubview(row)
        }
    }

    func refreshPermissions() {
        let ax = Permissions.hasAccessibility() ? "已授权" : "未授权"
        let screen = Permissions.hasScreenRecording() ? "已授权" : "未授权"
        permissionLabel.stringValue = "设备控制和数据访问：\(ax)\n录屏与系统录音：\(screen)"
    }

    // MARK: - 动作

    @objc private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            captureDirField.stringValue = url.path
        }
    }

    @objc private func addAllowEntry() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application, .unixExecutable]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let entry = SettingsWindowController.allowEntry(for: url)
            if !allowlist.contains(entry) { allowlist.append(entry) }
        }
        allowlist = allowlist.filter { !$0.isEmpty }
        rebuildAllowRows()
    }

    @objc private func removeAllowEntry(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < allowlist.count else { return }
        allowlist.remove(at: sender.tag)
        rebuildAllowRows()
    }

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
            "version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
            "config: \(Paths.configURL.path)",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func openAuditLog() {
        NSWorkspace.shared.open(Paths.auditURL)
    }

    @objc private func saveClicked() {
        var updated = config
        updated.holdToAuthSeconds = min(5.0, max(1.0, Double(holdField.stringValue) ?? 2.0))
        updated.hideCursorDuringCurtain = hideCursorSwitch.state == .on
        updated.captureDirectory = captureDirField.stringValue.trimmingCharacters(in: .whitespaces)
        updated.captureCursor = captureCursorSwitch.state == .on
        updated.recordingFPS = min(60, max(1, Int(fpsField.stringValue) ?? 30))
        updated.recordingBitrate = max(0, Int(bitrateField.stringValue) ?? 0)
        updated.allowlist = allowlist

        config = updated
        updated.save()
        onSave?(updated)
        window?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        loadValues()
        window?.orderOut(nil)
    }

    // MARK: - 工具

    static func allowEntry(for url: URL) -> String {
        if url.pathExtension.lowercased() == "app",
           let bundle = Bundle(url: url),
           let identifier = bundle.bundleIdentifier {
            return identifier
        }
        return url.path
    }
}
