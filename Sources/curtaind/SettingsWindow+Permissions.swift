import AppKit
import CurtainKit

extension SettingsWindowController {
    func makePermissionPage() -> NSView {
        accessibilityRow.setGranted(hasAccessibility)
        screenRecordingRow.setGranted(hasScreenRecording)
        permissionActionButton.target = self
        permissionActionButton.action = #selector(openPermissions)

        let actionTitle = CurtainTheme.label(
            "在系统设置中完成授权",
            size: 12.5,
            weight: .semibold
        )
        let actionDetail = CurtainTheme.label(
            "打开系统设置后，Curtain 会显示一个可拖拽图标。重装后如果列表里已有旧项，先移除旧版，再把当前 Curtain.app 拖入列表。",
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        let actionText = CurtainTheme.stack([actionTitle, actionDetail], spacing: 4)
        let actionStack = CurtainTheme.stack(
            [actionText, permissionActionButton],
            spacing: 14,
            alignment: .leading
        )
        actionText.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true
        let actionContainer = NSView()
        actionContainer.addSubview(actionStack)
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionStack.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: actionContainer.topAnchor, constant: 12),
            actionStack.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor, constant: -10),
        ])
        let permissionCard = card(
            containing: [accessibilityRow, screenRecordingRow, actionContainer]
        )

        return page(views: [permissionCard], spacing: CurtainTheme.sectionSpacing)
    }

    func makeDiagnosticsPage() -> NSView {
        diagnosticsHotkeyValue.stringValue = hotkeyDisplay
        let versionCard = card(containing: [
            diagnosticRow(title: "版本", value: "\(Self.version) (\(Self.build))"),
            diagnosticRow(title: "显示器", value: "\(NSScreen.screens.count) 块"),
            diagnosticRow(
                title: "快捷键",
                valueView: diagnosticsHotkeyValue
            ),
            diagnosticRow(
                title: "默认幕帘",
                valueView: diagnosticsModeValue
            ),
        ])

        let copyButton = CurtainButton(
            title: "复制诊断信息",
            symbol: "doc.on.doc",
            style: .secondary,
            target: self,
            action: #selector(copyDiagnostics)
        )
        let auditButton = CurtainButton(
            title: "打开审计日志",
            symbol: "list.bullet.rectangle",
            style: .secondary,
            target: self,
            action: #selector(openAuditLog)
        )
        let configButton = CurtainButton(
            title: "打开配置文件",
            symbol: "doc.badge.gearshape",
            style: .secondary,
            target: self,
            action: #selector(openConfigFile)
        )
        let buttons = CurtainTheme.stack(
            [copyButton, auditButton, configButton],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )
        let pathLabel = NSTextField(labelWithString: Paths.configURL.path)
        pathLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        pathLabel.textColor = CurtainTheme.tertiaryInk
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        let diagnosticsCard = CurtainCardView()
        let diagnosticsStack = CurtainTheme.stack(
            [buttons, pathLabel],
            spacing: 14
        )
        diagnosticsCard.contentView.addSubview(diagnosticsStack)
        pin(diagnosticsStack, to: diagnosticsCard.contentView)
        buttons.widthAnchor.constraint(equalTo: diagnosticsStack.widthAnchor).isActive = true
        pathLabel.widthAnchor.constraint(equalTo: diagnosticsStack.widthAnchor).isActive = true

        return page(views: [versionCard, diagnosticsCard], spacing: CurtainTheme.sectionSpacing)
    }

    func refreshPermissions() {
        hasAccessibility = Permissions.hasAccessibility()
        hasScreenRecording = Permissions.hasScreenRecording()
        accessibilityRow.setGranted(hasAccessibility)
        screenRecordingRow.setGranted(hasScreenRecording)
        let ready = hasAccessibility && hasScreenRecording
        sidebarPill.update(
            text: ready ? "权限就绪" : "需要授权",
            color: ready ? CurtainTheme.success : CurtainTheme.warning
        )
        headerPill.update(
            text: ready ? "已就绪" : "未完成",
            color: ready ? CurtainTheme.success : CurtainTheme.danger
        )
        permissionActionButton.setTitle(ready ? "重新检查" : "打开系统设置")
        permissionActionButton.image = NSImage(
            systemSymbolName: ready ? "arrow.clockwise" : "gearshape",
            accessibilityDescription: nil
        )
    }

    func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    @objc func openPermissions() {
        if Permissions.hasAccessibility(), Permissions.hasScreenRecording() {
            refreshPermissions()
            return
        }
        onOpenPermissions?()
    }

    @objc func copyDiagnostics() {
        let lines = [
            "accessibility: \(Permissions.hasAccessibility() ? "granted" : "missing")",
            "screen_recording: \(Permissions.hasScreenRecording() ? "granted" : "missing")",
            "displays: \(NSScreen.screens.count)",
            "hold_to_auth: \(holdField.value)",
            "double_escape: \(doubleField.value)",
            "curtain_color: \(curtainColorHex)",
            "hotkey: \(hotkeyDisplay)",
            "hide_cursor: \(hideCursorSwitch.state == .on)",
            "clamshell: \(clamshellSwitch.state == .on)",
            "idle_auto: \(idleSwitch.state == .on)",
            "idle_minutes: \(Int(idleMinutesField.value.rounded()))",
            "schedule: \(scheduleSwitch.state == .on)",
            "schedule_start: \(minutes(from: scheduleStartPicker))",
            "schedule_end: \(minutes(from: scheduleEndPicker))",
            "schedule_weekdays: \(selectedWeekdays)",
            "default_protection_minutes: \(Int(protectionMinutesField.value.rounded()))",
            "presentation_mode: \(presentationSwitch.state == .on)",
            "presentation_image: \(presentationImagePath)",
            "presentation_clock: \(selectedClockStyle.rawValue)",
            "presentation_main_role: \(selectedRole(mainRolePopup).rawValue)",
            "presentation_secondary_role: \(selectedRole(secondaryRolePopup).rawValue)",
            "presentation_focus: \(focusXField.value),\(focusYField.value)",
            "presentation_zoom: \(zoomField.value)",
            "presentation_dim: \(dimField.value)",
            "version: \(Self.version)",
            "config: \(Paths.configURL.path)",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc func openAuditLog() {
        NSWorkspace.shared.open(Paths.auditURL)
    }

    @objc func openConfigFile() {
        NSWorkspace.shared.open(Paths.configURL)
    }
}
