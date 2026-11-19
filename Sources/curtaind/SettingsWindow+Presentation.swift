import AppKit
import CurtainKit
import UniformTypeIdentifiers

extension SettingsWindowController {
    func makePresentationPage() -> NSView {
        configureRolePopup(mainRolePopup)
        configureRolePopup(secondaryRolePopup)
        for slider in [focusXField, focusYField, zoomField, dimField] {
            slider.onChange = { [weak self] in
                self?.presentationAdjustmentsChanged()
            }
        }
        presentationSwitch.target = self
        presentationSwitch.action = #selector(presentationChanged)
        presentationImageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        presentationImageLabel.textColor = CurtainTheme.secondaryInk
        presentationImageLabel.lineBreakMode = .byTruncatingMiddle
        presentationImageButton.target = self
        presentationImageButton.action = #selector(choosePresentationImage)
        presentationClearButton.target = self
        presentationClearButton.action = #selector(clearPresentationImage)
        clockStylePicker.onSelect = { [weak self] style in
            self?.clockStyleChanged(style)
        }
        previewPresentationButton.target = self
        previewPresentationButton.action = #selector(previewPresentation)

        let imageControls = NSStackView()
        imageControls.orientation = .horizontal
        imageControls.spacing = 8
        imageControls.addArrangedSubview(presentationImageLabel)
        imageControls.addArrangedSubview(presentationImageButton)
        imageControls.addArrangedSubview(presentationClearButton)
        presentationImageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let switchRow = CurtainSettingRow(
            title: "启用窗口展示模式",
            detail: "默认关闭。关闭时使用输出层 gamma 幕帘；开启后显示自定义背景和完整时钟。",
            control: presentationSwitch
        )
        let imageRow = CurtainSettingRow(
            title: "背景图片",
            detail: "选择本地图片后等比铺满；未选择时使用默认幕帘颜色。",
            control: imageControls
        )
        let mainRoleRow = CurtainSettingRow(
            title: "主屏角色",
            detail: "选择实时时钟展示，或保持纯黑输出层幕帘。",
            control: mainRolePopup,
            verticalInset: 7
        )
        let secondaryRoleRow = CurtainSettingRow(
            title: "副屏角色",
            detail: "多屏时其余显示器统一使用这里的角色。",
            control: secondaryRolePopup,
            verticalInset: 7
        )
        let focusXRow = CurtainSettingRow(
            title: "横向焦点",
            detail: "决定放大时保留画面的左侧或右侧。",
            control: focusXField,
            verticalInset: 7
        )
        let focusYRow = CurtainSettingRow(
            title: "纵向焦点",
            detail: "决定放大时保留画面的上方或下方。",
            control: focusYField,
            verticalInset: 7
        )
        let zoomRow = CurtainSettingRow(
            title: "背景缩放",
            detail: "在不改变屏幕比例的前提下放大背景图。",
            control: zoomField,
            verticalInset: 7
        )
        let dimRow = CurtainSettingRow(
            title: "额外暗化",
            detail: "让时钟与文字在明亮背景上保持可读。",
            control: dimField,
            verticalInset: 7
        )
        let clockTitle = CurtainTheme.label(
            "时钟样式",
            size: 12.5,
            weight: .medium
        )
        let clockDetail = CurtainTheme.label(
            "三种样式都会显示年、月、日、时、分、秒、星期和农历。",
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        let clockStack = CurtainTheme.stack(
            [clockTitle, clockDetail, clockStylePicker],
            spacing: 6
        )
        let clockContainer = NSView()
        clockContainer.addSubview(clockStack)
        clockStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clockStack.leadingAnchor.constraint(equalTo: clockContainer.leadingAnchor),
            clockStack.trailingAnchor.constraint(equalTo: clockContainer.trailingAnchor),
            clockStack.topAnchor.constraint(equalTo: clockContainer.topAnchor, constant: 8),
            clockStack.bottomAnchor.constraint(equalTo: clockContainer.bottomAnchor, constant: -6),
        ])
        let basicCard = card(containing: [switchRow, imageRow])
        let advancedCard = card(containing: [
            clockContainer,
            twoColumnRow(mainRoleRow, secondaryRoleRow),
            twoColumnRow(focusXRow, focusYRow),
            twoColumnRow(zoomRow, dimRow),
        ])
        clockStylePicker.widthAnchor.constraint(equalTo: clockStack.widthAnchor).isActive = true

        let previewCard = CurtainCardView(
            padding: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        )
        previewCard.contentView.addSubview(presentationPreview)
        pin(presentationPreview, to: previewCard.contentView)
        presentationPreview.heightAnchor.constraint(equalToConstant: 200).isActive = true
        previewCard.contentView.addSubview(previewPresentationButton)
        NSLayoutConstraint.activate([
            previewPresentationButton.topAnchor.constraint(
                equalTo: previewCard.contentView.topAnchor,
                constant: 12
            ),
            previewPresentationButton.trailingAnchor.constraint(
                equalTo: previewCard.contentView.trailingAnchor,
                constant: -12
            ),
        ])

        updatePresentationControls()
        return page(
            views: [basicCard, previewCard, advancedCard],
            spacing: CurtainTheme.sectionSpacing
        )
    }

    func updatePresentationControls() {
        let presentationEnabled = presentationSwitch.state == .on
        presentationImageButton.title = presentationImagePath.isEmpty
            ? "选择图片…"
            : "更换图片…"
        presentationImageButton.isEnabled = presentationEnabled
        presentationClearButton.isEnabled = presentationEnabled
            && !presentationImagePath.isEmpty
        mainRolePopup.isEnabled = presentationEnabled
        secondaryRolePopup.isEnabled = presentationEnabled
        focusXField.isEnabled = presentationEnabled
        focusYField.isEnabled = presentationEnabled
        zoomField.isEnabled = presentationEnabled
        dimField.isEnabled = presentationEnabled
        clockStylePicker.alphaValue = presentationEnabled ? 1 : 0.5
        presentationPreview.alphaValue = 1
    }

    func configureRolePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItems(withTitles: CurtainDisplayRole.allCases.map(\.displayName))
        popup.controlSize = .small
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 132).isActive = true
    }

    func selectedRole(_ popup: NSPopUpButton) -> CurtainDisplayRole {
        let roles = CurtainDisplayRole.allCases
        guard roles.indices.contains(popup.indexOfSelectedItem) else {
            return .presentation
        }
        return roles[popup.indexOfSelectedItem]
    }

    func refreshPresentationPreview(startedAt: Date? = nil) {
        presentationPreview.update(
            color: colorWell.color,
            imagePath: presentationImagePath,
            clockStyle: selectedClockStyle,
            imageFocus: CGPoint(
                x: focusXField.value,
                y: focusYField.value
            ),
            imageZoom: zoomField.value,
            imageDim: dimField.value,
            startedAt: startedAt
        )
    }

    @objc func presentationAdjustmentsChanged() {
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func presentationChanged() {
        diagnosticsModeValue.stringValue = presentationSwitch.state == .on
            ? "展示模式 · \(selectedClockStyle.displayName)"
            : "输出层 gamma"
        updatePresentationControls()
        refreshPresentationPreview()
        refreshScenePreview()
    }

    func clockStyleChanged(_ style: PresentationClockStyle) {
        diagnosticsModeValue.stringValue = presentationSwitch.state == .on
            ? "展示模式 · \(style.displayName)"
            : "输出层 gamma"
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func previewPresentation() {
        let imagePath = presentationImagePath
        if !imagePath.isEmpty,
           !PresentationBackgroundLoader.isLoadable(path: imagePath) {
            presentAlert(
                title: "背景图无法读取",
                message: "请选择有效的图片文件，或清除路径改用纯色背景。"
            )
            return
        }
        guard let onPreviewPresentation else {
            presentAlert(
                title: "全屏试看不可用",
                message: "请从 Curtain 的设置窗口打开此页面。"
            )
            return
        }
        let color = colorWell.color.usingColorSpace(.sRGB) ?? .black
        onPreviewPresentation(
            PresentationPreviewConfiguration(
                color: CurtainColor(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                ),
                imagePath: imagePath.isEmpty ? nil : imagePath,
                clockStyle: selectedClockStyle,
                imageFocus: CGPoint(
                    x: focusXField.value,
                    y: focusYField.value
                ),
                imageZoom: zoomField.value,
                imageDim: dimField.value,
                duration: 8
            )
        )
    }

    @objc func choosePresentationImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "使用这张图片"
        if panel.runModal() == .OK, let url = panel.url {
            presentationImagePath = url.path
            presentationImageLabel.stringValue = url.lastPathComponent
            refreshPresentationPreview()
            refreshScenePreview()
            updatePresentationControls()
        }
    }

    @objc func clearPresentationImage() {
        presentationImagePath = ""
        presentationImageLabel.stringValue = "纯色背景"
        refreshPresentationPreview()
        refreshScenePreview()
        updatePresentationControls()
    }

    @objc func resetColor() {
        colorWell.color = .black
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func colorChanged() {
        refreshPresentationPreview()
        refreshScenePreview()
    }

    var selectedClockStyle: PresentationClockStyle {
        clockStylePicker.selectedStyle
    }
}
