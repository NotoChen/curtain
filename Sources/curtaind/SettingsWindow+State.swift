import AppKit
import CurtainKit

extension SettingsWindowController {
    func loadValues() {
        doubleField.value = config.doubleEscapeSeconds
        holdField.value = config.holdToAuthSeconds
        colorWell.color = nsColor(from: config.curtainColor)
        hideCursorSwitch.state = config.hideCursorDuringCurtain ? .on : .off
        clamshellSwitch.state = config.clamshellModeEnabled ? .on : .off
        idleSwitch.state = config.idleAutoCurtainEnabled ? .on : .off
        idleMinutesField.value = config.idleAutoCurtainSeconds / 60
        scheduleSwitch.state = config.scheduleEnabled ? .on : .off
        scheduleStartPicker.dateValue = date(fromMinutes: config.scheduleStartMinutes)
        scheduleEndPicker.dateValue = date(fromMinutes: config.scheduleEndMinutes)
        scheduleAutoExitSwitch.state = config.scheduleAutoExit ? .on : .off
        protectionMinutesField.value = Double(config.defaultProtectionMinutes)
        for button in weekdayButtons {
            button.state = (config.scheduleWeekdays & (1 << button.tag)) != 0
                ? .on
                : .off
        }
        presentationSwitch.state = config.presentationModeEnabled ? .on : .off
        mainRolePopup.selectItem(
            at: CurtainDisplayRole.allCases.firstIndex(
                of: CurtainDisplayRole.storedValue(config.mainDisplayRole)
            ) ?? 0
        )
        secondaryRolePopup.selectItem(
            at: CurtainDisplayRole.allCases.firstIndex(
                of: CurtainDisplayRole.storedValue(config.secondaryDisplayRole)
            ) ?? 0
        )
        focusXField.value = config.presentationFocusX
        focusYField.value = config.presentationFocusY
        zoomField.value = config.presentationZoom
        dimField.value = config.presentationDim
        presentationImagePath = config.presentationImagePath
        let clockStyle = PresentationClockStyle.storedValue(
            config.presentationClockStyle
        )
        clockStylePicker.selectedStyle = clockStyle
        presentationImageLabel.stringValue = presentationImagePath.isEmpty
            ? "纯色背景"
            : URL(fileURLWithPath: presentationImagePath).lastPathComponent
        loadSceneProfiles()
        hotkeyButton.binding = HotkeyBinding(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        diagnosticsHotkeyValue.stringValue = hotkeyDisplay
        diagnosticsModeValue.stringValue = config.presentationModeEnabled
            ? "展示模式 · \(clockStyle.displayName)"
            : "输出层 gamma"
        refreshPresentationPreview()
        updateAutomationControls()
        updatePresentationControls()
        updateDirtyState()
    }

    func startDirtyTracking() {
        guard dirtyTimer == nil else {
            updateDirtyState()
            return
        }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.updateDirtyState()
        }
        RunLoop.main.add(timer, forMode: .common)
        dirtyTimer = timer
        updateDirtyState()
    }

    func stopDirtyTracking() {
        dirtyTimer?.invalidate()
        dirtyTimer = nil
    }

    func updateDirtyState() {
        let invalidInput = hasInvalidInput
        let dirty = hasUnsavedChanges
        window?.isDocumentEdited = dirty
        if invalidInput {
            footerNote.stringValue = "请输入范围内的有效数值"
            footerNote.textColor = CurtainTheme.danger
        } else {
            footerNote.stringValue = dirty
                ? "有未保存的更改 · ⌘S 保存"
                : "⌘1–⌘6 切换页面 · Esc 关闭"
            footerNote.textColor = dirty
                ? CurtainTheme.accent
                : CurtainTheme.tertiaryInk
        }
        saveButton.isEnabled = dirty && !invalidInput
        cancelButton.setTitle(dirty ? "取消" : "关闭")
        cancelButton.toolTip = dirty ? "放弃未保存的修改" : "关闭设置"
    }

    func startKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  event.window === self.window else {
                return event
            }
            let flags = event.modifierFlags.intersection(
                .deviceIndependentFlagsMask
            )
            if event.keyCode == 53, flags.isEmpty {
                self.requestClose()
                return nil
            }
            guard flags.contains(.command),
                  !flags.contains(.control),
                  !flags.contains(.option),
                  let character = event.charactersIgnoringModifiers?
                    .lowercased() else {
                return event
            }
            if character == "s" {
                if self.hasUnsavedChanges {
                    self.saveClicked()
                }
                return nil
            }
            if let pageNumber = Int(character),
               (1...SettingsPage.allCases.count).contains(pageNumber) {
                self.select(SettingsPage.allCases[pageNumber - 1])
                return nil
            }
            return event
        }
    }

    func stopKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    var hotkeyDisplay: String {
        HotkeyPolicy.displayString(
            keyCode: hotkeyButton.binding.keyCode,
            modifiers: hotkeyButton.binding.modifiers
        )
    }

    func draftConfig() -> CurtainConfig {
        var updated = config
        updated.doubleEscapeSeconds = min(1.5, max(0.3, doubleField.value))
        updated.holdToAuthSeconds = min(5, max(1, holdField.value))
        updated.curtainColor = curtainColorHex
        updated.hideCursorDuringCurtain = hideCursorSwitch.state == .on
        updated.clamshellModeEnabled = clamshellSwitch.state == .on
        updated.idleAutoCurtainEnabled = idleSwitch.state == .on
        updated.idleAutoCurtainSeconds = min(
            86_400,
            max(60, idleMinutesField.value.rounded() * 60)
        )
        updated.scheduleEnabled = scheduleSwitch.state == .on
        updated.scheduleStartMinutes = minutes(from: scheduleStartPicker)
        updated.scheduleEndMinutes = minutes(from: scheduleEndPicker)
        let weekdays = selectedWeekdays
        updated.scheduleWeekdays = weekdays
        updated.scheduleAutoExit = scheduleAutoExitSwitch.state == .on
        updated.defaultProtectionMinutes = min(
            1440,
            max(0, Int(protectionMinutesField.value.rounded()))
        )
        commitSceneProfile()
        var sceneOverrides: [String: CurtainSceneProfile] = [:]
        for scene in CurtainScene.allCases {
            let profile = sceneProfiles[scene] ?? scene.defaultProfile
            if profile != scene.defaultProfile {
                sceneOverrides[scene.rawValue] = profile
            }
        }
        updated.sceneProfiles = sceneOverrides
        var customSceneHotkeys: [String: SceneHotkey] = [:]
        for scene in CurtainScene.allCases {
            let hotkey = sceneHotkeys[scene] ?? scene.defaultHotkey
            if hotkey != scene.defaultHotkey {
                customSceneHotkeys[scene.rawValue] = hotkey
            }
        }
        updated.sceneHotkeys = customSceneHotkeys
        updated.presentationModeEnabled = presentationSwitch.state == .on
        updated.presentationImagePath = presentationImagePath
        updated.presentationClockStyle = selectedClockStyle.rawValue
        updated.mainDisplayRole = selectedRole(mainRolePopup).rawValue
        updated.secondaryDisplayRole = selectedRole(secondaryRolePopup).rawValue
        updated.presentationFocusX = focusXField.value
        updated.presentationFocusY = focusYField.value
        updated.presentationZoom = zoomField.value
        updated.presentationDim = dimField.value
        updated.hotkeyKeyCode = hotkeyButton.binding.keyCode
        updated.hotkeyModifiers = hotkeyButton.binding.modifiers.rawValue
        return updated
    }

    @objc func saveClicked() {
        if persistChanges() {
            dismissWindow()
        }
    }

    func persistChanges() -> Bool {
        if hasInvalidInput {
            NSSound.beep()
            return false
        }
        window?.makeFirstResponder(nil)
        let imagePath = presentationImagePath
        if presentationSwitch.state == .on,
           !imagePath.isEmpty,
           !PresentationBackgroundLoader.isLoadable(path: imagePath) {
            presentAlert(
                title: "背景图无法读取",
                message: "请选择有效的图片文件，或清除路径改用纯色背景。"
            )
            return false
        }
        if !hotkeyButton.binding.isValid {
            presentAlert(
                title: "快捷键不可用",
                message: "请使用包含 Control、Option 或 Command 的组合键。"
            )
            return false
        }
        let sceneBindings = CurtainScene.allCases.map {
            ($0, (sceneHotkeys[$0] ?? $0.defaultHotkey).binding)
        }
        for (index, entry) in sceneBindings.enumerated() {
            if entry.1 == hotkeyButton.binding {
                presentAlert(
                    title: "场景快捷键冲突",
                    message: "「\(entry.0.title)」的场景快捷键不能和起幕/撤幕快捷键相同。"
                )
                return false
            }
            for other in sceneBindings.dropFirst(index + 1)
                where entry.1 == other.1 {
                presentAlert(
                    title: "场景快捷键冲突",
                    message: "「\(entry.0.title)」和「\(other.0.title)」使用了同一个快捷键。"
                )
                return false
            }
        }
        let weekdays = selectedWeekdays
        if scheduleSwitch.state == .on, weekdays == 0 {
            presentAlert(
                title: "至少选择一天",
                message: "每日定时保护开启时需要选择至少一个星期。"
            )
            return false
        }

        let updated = draftConfig()
        for scene in CurtainScene.allCases {
            let profile = updated.sceneProfile(for: scene)
            guard profile.usesPresentation,
                  !profile.backgroundImagePath.isEmpty,
                  !PresentationBackgroundLoader.isLoadable(
                    path: profile.backgroundImagePath
                  ) else {
                continue
            }
            presentAlert(
                title: "场景背景图无法读取",
                message: "「\(scene.title)」的背景图不可用，请重新选择或改为跟随全局背景。"
            )
            return false
        }

        if let error = updated.save() {
            presentAlert(title: "设置保存失败", message: error)
            return false
        }
        config = updated
        hasLoadedValues = true
        updateDirtyState()
        onSave?(updated)
        return true
    }

    @objc func cancelClicked() {
        loadValues()
        hasLoadedValues = true
        dismissWindow()
    }

    func dismissWindow() {
        stopPermissionPolling()
        stopDirtyTracking()
        stopKeyboardMonitor()
        window?.orderOut(nil)
    }

    var hasUnsavedChanges: Bool {
        hasInvalidInput || draftConfig() != config
    }

    var hasInvalidInput: Bool {
        numberFields.contains { !$0.isValid }
    }

    var curtainColorHex: String {
        guard let color = colorWell.color.usingColorSpace(.sRGB) else {
            return config.curtainColor
        }
        return CurtainColor(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        ).hex
    }

    func sceneTint(_ scene: CurtainScene) -> NSColor {
        switch scene {
        case .away: return CurtainTheme.accent
        case .meeting: return CurtainTheme.warning
        case .guest: return CurtainTheme.success
        case .focus: return CurtainTheme.focus
        }
    }

    var selectedWeekdays: Int {
        weekdayButtons.reduce(0) { result, button in
            result | (button.state == .on ? (1 << button.tag) : 0)
        }
    }

    func nsColor(from hex: String) -> NSColor {
        let color = CurtainColor(hex: hex) ?? .black
        return NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: 1
        )
    }

    func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
