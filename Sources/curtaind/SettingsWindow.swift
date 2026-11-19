import AppKit
import CurtainKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSave: ((CurtainConfig) -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onPreviewPresentation: ((PresentationPreviewConfiguration) -> Void)?

    var config: CurtainConfig
    var selectedPage: SettingsPage = .general
    var pages: [SettingsPage: NSView] = [:]
    var navRows: [SettingsPage: CurtainNavRow] = [:]
    var permissionTimer: Timer?
    var dirtyTimer: Timer?
    var keyboardMonitor: Any?
    var hasLoadedValues = false
    var hasAccessibility = Permissions.hasAccessibility()
    var hasScreenRecording = Permissions.hasScreenRecording()
    var presentationImagePath = ""

    let headerTitle = NSTextField(labelWithString: "")
    let headerSubtitle = NSTextField(labelWithString: "")
    let headerPill = CurtainStatusPillView(text: "未完成", color: CurtainTheme.danger)
    let sidebarPill = CurtainStatusPillView(text: "需要授权", color: CurtainTheme.warning)
    let pageHost = NSView()
    let scrollView = NSScrollView()
    let footerNote = NSTextField(
        labelWithString: "保存后立即生效，不需要重开 Curtain。"
    )
    let cancelButton = CurtainButton(
        title: "取消",
        style: .secondary,
        target: nil,
        action: nil
    )
    let saveButton = CurtainButton(
        title: "保存",
        style: .primary,
        target: nil,
        action: nil
    )

    let doubleField = CurtainNumberField(
        value: 0.7,
        suffix: "秒",
        range: 0.3...1.5
    )
    let holdField = CurtainNumberField(
        value: 2.0,
        suffix: "秒",
        range: 1...5
    )
    let colorWell = NSColorWell()
    let hideCursorSwitch = NSSwitch()
    let clamshellSwitch = NSSwitch()
    let idleSwitch = NSSwitch()
    let idleMinutesField = CurtainNumberField(
        value: 10,
        suffix: "分钟",
        range: 1...1440,
        decimalPlaces: 0
    )
    let scheduleSwitch = NSSwitch()
    let scheduleStartPicker = NSDatePicker()
    let scheduleEndPicker = NSDatePicker()
    let scheduleAutoExitSwitch = NSSwitch()
    let protectionMinutesField = CurtainNumberField(
        value: 0,
        suffix: "分钟",
        range: 0...1440,
        decimalPlaces: 0
    )
    var sceneProfiles: [CurtainScene: CurtainSceneProfile] = Dictionary(
        uniqueKeysWithValues: CurtainScene.allCases.map {
            ($0, $0.defaultProfile)
        }
    )
    var sceneHotkeys: [CurtainScene: SceneHotkey] = [:]
    var selectedScene: CurtainScene = .away
    let sceneSelector = NSSegmentedControl()
    let sceneDetailLabel = NSTextField(labelWithString: "")
    let sceneResetButton = CurtainButton(
        title: "恢复默认",
        style: .secondary,
        target: nil,
        action: nil
    )
    let sceneMinuteField = CurtainNumberField(
        value: 120,
        suffix: "分钟",
        range: 0...1440,
        decimalPlaces: 0
    )
    let scenePresentationPopup = NSPopUpButton()
    let sceneClockPopup = NSPopUpButton()
    let sceneImageLabel = NSTextField(labelWithString: "跟随全局背景")
    let sceneImageButton = CurtainButton(
        title: "选择图片…",
        style: .secondary,
        target: nil,
        action: nil
    )
    let sceneImageClearButton = CurtainButton(
        title: "跟随全局",
        style: .secondary,
        target: nil,
        action: nil
    )
    let sceneMessageField = NSTextField()
    let sceneReturnSwitch = NSSwitch()
    let sceneMainRolePopup = NSPopUpButton()
    let sceneSecondaryRolePopup = NSPopUpButton()
    let scenePreview = CurtainPresentationPreviewView()
    var weekdayButtons: [NSButton] = []
    let presentationSwitch = NSSwitch()
    let presentationImageLabel = NSTextField(labelWithString: "纯色背景")
    let presentationPreview = CurtainPresentationPreviewView()
    let clockStylePicker = ClockStylePickerView()
    let mainRolePopup = NSPopUpButton()
    let secondaryRolePopup = NSPopUpButton()
    let focusXField = CurtainSliderField(
        minimum: 0,
        maximum: 1,
        value: 0.5,
        width: 180,
        sliderWidth: 122,
        formatter: { String(format: "%.0f%%", $0 * 100) }
    )
    let focusYField = CurtainSliderField(
        minimum: 0,
        maximum: 1,
        value: 0.5,
        width: 180,
        sliderWidth: 122,
        formatter: { String(format: "%.0f%%", $0 * 100) }
    )
    let zoomField = CurtainSliderField(
        minimum: 1,
        maximum: 2,
        value: 1,
        width: 180,
        sliderWidth: 122,
        formatter: { String(format: "%.2f×", $0) }
    )
    let dimField = CurtainSliderField(
        minimum: 0,
        maximum: 0.8,
        value: 0,
        width: 180,
        sliderWidth: 122,
        formatter: { String(format: "%.0f%%", $0 * 100) }
    )
    let previewPresentationButton = CurtainButton(
        title: "全屏试看",
        symbol: "play.rectangle.fill",
        style: .primary,
        target: nil,
        action: nil
    )
    let presentationImageButton = CurtainButton(
        title: "选择图片…",
        style: .secondary,
        target: nil,
        action: nil
    )
    let presentationClearButton = CurtainButton(
        title: "清除",
        style: .secondary,
        target: nil,
        action: nil
    )
    let accessibilityRow = PermissionStateRowView(
        symbol: "keyboard",
        title: "设备控制和数据访问",
        detail: "拦截物理键盘鼠标、识别 Esc 手势，并保护幕帘期间的输入边界。",
        granted: false
    )
    let screenRecordingRow = PermissionStateRowView(
        symbol: "rectangle.dashed.badge.record",
        title: "录屏与系统录音",
        detail: "供 Agent 通过 curtainctl 截图和录屏，普通调用方不会直接获得权限。",
        granted: false
    )
    let permissionActionButton = CurtainButton(
        title: "打开系统设置",
        symbol: "gearshape",
        style: .primary,
        target: nil,
        action: nil
    )
    let diagnosticsHotkeyValue = NSTextField(labelWithString: "")
    let diagnosticsModeValue = NSTextField(labelWithString: "")

    var numberFields: [CurtainNumberField] {
        [
            doubleField,
            holdField,
            idleMinutesField,
            protectionMinutesField,
            sceneMinuteField,
        ]
    }

    lazy var hotkeyButton = HotkeyRecorderButton(
        binding: HotkeyBinding(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
    )
    lazy var sceneHotkeyButton = HotkeyRecorderButton(
        binding: config.sceneHotkey(for: .away).binding
    )

    init(config: CurtainConfig) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 820),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        CurtainWindowChrome.apply(to: window, title: "Curtain 设置")
        window.minSize = NSSize(width: 820, height: 620)
        CurtainWindowChrome.centerOnActiveScreen(window)
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if !hasLoadedValues {
            loadValues()
            hasLoadedValues = true
        }
        refreshPermissions()
        startPermissionPolling()
        startDirtyTracking()
        startKeyboardMonitor()
        if let window {
            CurtainWindowChrome.centerOnActiveScreen(window)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        dismissWindow()
    }

#if DEBUG
    func previewSelectPage(_ index: Int) {
        let pages = SettingsPage.allCases
        guard pages.indices.contains(index) else { return }
        select(pages[index])
    }

    func previewSelectScene(_ scene: CurtainScene) {
        selectedScene = scene
        loadSelectedScene()
    }

    func previewSetDirty() {
        doubleField.value += 0.1
        updateDirtyState()
    }
#endif

    func windowWillClose(_ notification: Notification) {
        stopPermissionPolling()
        stopDirtyTracking()
        stopKeyboardMonitor()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }

    func requestClose() {
        guard hasUnsavedChanges else {
            dismissWindow()
            return
        }
        let alert = NSAlert()
        alert.messageText = "保存对设置的更改？"
        alert.informativeText = "不保存会丢失当前修改。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if persistChanges() {
                dismissWindow()
            }
        case .alertSecondButtonReturn:
            loadValues()
            dismissWindow()
        default:
            break
        }
    }

    deinit {
        stopPermissionPolling()
        stopDirtyTracking()
        stopKeyboardMonitor()
    }

    private func buildUI() {
        guard let window else { return }
        let root = NSView()
        root.wantsLayer = true
        root.addSubview(CurtainBackdropView())
        root.subviews[0].translatesAutoresizingMaskIntoConstraints = false

        let sidebar = buildSidebar()
        root.addSubview(sidebar)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarDivider = NSView()
        sidebarDivider.wantsLayer = true
        sidebarDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(sidebarDivider)
        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false

        let detail = buildDetail()
        root.addSubview(detail)
        detail.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.subviews[0].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            root.subviews[0].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.subviews[0].topAnchor.constraint(equalTo: root.topAnchor),
            root.subviews[0].bottomAnchor.constraint(equalTo: root.bottomAnchor),

            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),

            sidebarDivider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarDivider.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 0.7),

            detail.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        pages = [
            .general: makeGeneralPage(),
            .automation: makeAutomationPage(),
            .scenes: makeScenesPage(),
            .presentation: makePresentationPage(),
            .permissions: makePermissionPage(),
            .diagnostics: makeDiagnosticsPage(),
        ]
        window.contentView = root
        for field in numberFields where field !== sceneMinuteField {
            field.onChange = { [weak self] in
                self?.updateDirtyState()
            }
        }
        select(.general)
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .followsWindowActiveState

        let icon = CurtainBrandIconView(size: 38)
        let name = NSTextField(labelWithString: "CURTAIN")
        name.font = .systemFont(ofSize: 13, weight: .bold)
        name.attributedStringValue = NSAttributedString(
            string: "CURTAIN",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .kern: 1.4,
                .foregroundColor: CurtainTheme.ink,
            ]
        )
        let subtitle = NSTextField(labelWithString: "可见性开关")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = CurtainTheme.secondaryInk
        let brandText = CurtainTheme.stack([name, subtitle], spacing: 1)
        let brand = CurtainTheme.stack(
            [icon, brandText],
            orientation: .horizontal,
            spacing: 13,
            alignment: .centerY
        )

        let nav = NSStackView()
        nav.orientation = .vertical
        nav.spacing = 5
        nav.alignment = .leading
        nav.translatesAutoresizingMaskIntoConstraints = false
        for page in SettingsPage.allCases {
            let row = CurtainNavRow(symbol: page.symbol, title: page.title)
            row.onClick = { [weak self] in self?.select(page) }
            navRows[page] = row
            nav.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
        }
        for (index, page) in SettingsPage.allCases.enumerated() {
            navRows[page]?.toolTip = "\(page.title)（⌘\(index + 1)）"
        }

        let version = NSTextField(labelWithString: "Curtain \(Self.version)")
        version.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        version.textColor = CurtainTheme.tertiaryInk
        let footer = CurtainTheme.stack([sidebarPill, version], spacing: 10)

        sidebar.addSubview(brand)
        sidebar.addSubview(nav)
        sidebar.addSubview(footer)
        brand.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -16),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 46),

            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 30),

            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24),
        ])
        return sidebar
    }

    private func buildDetail() -> NSView {
        let detail = NSView()

        headerTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        headerTitle.textColor = CurtainTheme.ink
        headerSubtitle.font = .systemFont(ofSize: 11.5)
        headerSubtitle.textColor = CurtainTheme.secondaryInk
        headerSubtitle.maximumNumberOfLines = 2
        headerSubtitle.lineBreakMode = .byWordWrapping
        let headerText = CurtainTheme.stack([headerTitle, headerSubtitle], spacing: 4)

        detail.addSubview(headerText)
        detail.addSubview(headerPill)
        detail.addSubview(scrollView)
        headerText.translatesAutoresizingMaskIntoConstraints = false
        headerPill.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(pageHost)
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let footerDivider = CurtainDividerView()
        footerNote.font = .systemFont(ofSize: 9.5)
        footerNote.textColor = CurtainTheme.tertiaryInk
        footerNote.lineBreakMode = .byTruncatingTail
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.toolTip = "放弃未保存的修改"
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.toolTip = "保存设置（⌘S）"
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footerButtons = CurtainTheme.stack(
            [footerNote, footerSpacer, cancelButton, saveButton],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )
        detail.addSubview(footerDivider)
        detail.addSubview(footerButtons)
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerButtons.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerText.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 32),
            headerText.topAnchor.constraint(equalTo: detail.topAnchor, constant: 40),
            headerText.trailingAnchor.constraint(lessThanOrEqualTo: headerPill.leadingAnchor, constant: -18),

            headerPill.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -32),
            headerPill.centerYAnchor.constraint(equalTo: headerTitle.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 32),
            scrollView.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -32),
            scrollView.topAnchor.constraint(equalTo: headerText.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -14),

            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            pageHost.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: document.topAnchor),
            pageHost.bottomAnchor.constraint(equalTo: document.bottomAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 32),
            footerDivider.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -32),
            footerDivider.bottomAnchor.constraint(equalTo: footerButtons.topAnchor, constant: -14),

            footerButtons.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 32),
            footerButtons.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -32),
            footerButtons.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -18),
        ])
        return detail
    }

    func select(_ page: SettingsPage) {
        selectedPage = page
        for (key, row) in navRows {
            row.isSelected = key == page
        }
        headerTitle.stringValue = page.title
        headerSubtitle.stringValue = page.subtitle
        headerPill.isHidden = page != .permissions
        guard let selected = pages[page] else { return }
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        pageHost.addSubview(selected)
        selected.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            selected.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            selected.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            selected.topAnchor.constraint(equalTo: pageHost.topAnchor),
            selected.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
        ])
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}
