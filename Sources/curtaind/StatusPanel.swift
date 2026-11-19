import AppKit
import CurtainKit

struct DashboardSnapshot {
    var curtainState: CurtainState
    var recording: Bool
    var hotkey: String
    var elapsed: String
    var scene: CurtainScene?
    var sceneMinutes: [CurtainScene: Int]
    var scenePresentationLabels: [CurtainScene: String]
    var sceneHotkeys: [CurtainScene: String]
    var protectionRemaining: String?
    var presentationLabel: String
    var hasAccessibility: Bool
    var hasScreenRecording: Bool
    var version: String

    var permissionsReady: Bool {
        hasAccessibility && hasScreenRecording
    }
}

struct DashboardActions {
    let toggle: () -> Void
    let activateScene: (CurtainScene) -> Void
    let quickProtect: (Int) -> Void
    let stopRecording: () -> Void
    let permissions: () -> Void
    let settings: () -> Void
    let quit: () -> Void
}

final class StatusPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let actions: DashboardActions
    private var dashboard: DashboardViewController!
    private var lastContentSize: NSSize?

    init(provider: @escaping () -> DashboardSnapshot,
         actions: DashboardActions) {
        self.actions = actions
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 360)
        popover.delegate = self
        let wrapped = DashboardActions(
            toggle: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.toggle)
            },
            activateScene: { [weak self] scene in
                guard let self else { return }
                self.perform { self.actions.activateScene(scene) }
            },
            quickProtect: { [weak self] minutes in
                guard let self else { return }
                self.perform { self.actions.quickProtect(minutes) }
            },
            stopRecording: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.stopRecording)
            },
            permissions: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.permissions)
            },
            settings: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.settings)
            },
            quit: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.quit)
            }
        )
        dashboard = DashboardViewController(provider: provider, actions: wrapped)
        dashboard.onPreferredSizeChange = { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.applyPreferredSizeIfNeeded()
        }
        popover.contentViewController = dashboard
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }
        dashboard.start()
        applyPreferredSizeIfNeeded()
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        dashboard.stop()
    }

    private func applyPreferredSizeIfNeeded() {
        let size = dashboard.preferredPopoverSize
        guard size != lastContentSize else { return }
        lastContentSize = size
        popover.contentSize = size
    }

    private func perform(_ action: @escaping () -> Void) {
        close()
        DispatchQueue.main.async {
            action()
        }
    }
}

final class DashboardViewController: NSViewController {
    private let provider: () -> DashboardSnapshot
    private let actions: DashboardActions
    private var timer: Timer?
    private var snapshot: DashboardSnapshot?
    var onPreferredSizeChange: (() -> Void)?

    private let statusPill = CurtainStatusPillView(text: "待命", color: CurtainTheme.secondaryInk)
    private let hero = DashboardHeroView()
    private let quickPanel = DashboardQuickPanel()
    private let permissionCard = DashboardPermissionCard()
    private let versionLabel = NSTextField(labelWithString: "")

    init(provider: @escaping () -> DashboardSnapshot,
         actions: DashboardActions) {
        self.provider = provider
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 640))
        root.addSubview(CurtainBackdropView())
        root.subviews[0].translatesAutoresizingMaskIntoConstraints = false

        let icon = CurtainBrandIconView(size: 31)
        let name = NSTextField(labelWithString: "CURTAIN")
        name.attributedStringValue = NSAttributedString(
            string: "CURTAIN",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .kern: 1.5,
                .foregroundColor: CurtainTheme.ink,
            ]
        )
        let subtitle = NSTextField(labelWithString: "可见性开关")
        subtitle.font = .systemFont(ofSize: 9)
        subtitle.textColor = CurtainTheme.tertiaryInk
        let brandText = CurtainTheme.stack([name, subtitle], spacing: 1)
        let quitButton = CurtainIconButton(
            symbol: "power",
            accessibilityLabel: "退出 Curtain",
            target: self,
            action: #selector(quitClicked)
        )
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = CurtainTheme.stack(
            [icon, brandText, headerSpacer, statusPill, quitButton],
            orientation: .horizontal,
            spacing: 11,
            alignment: .centerY
        )

        hero.onToggle = { [weak self] in
            self?.actions.toggle()
        }
        hero.onStopRecording = { [weak self] in
            self?.actions.stopRecording()
        }
        quickPanel.onScene = { [weak self] scene in
            self?.actions.activateScene(scene)
        }
        quickPanel.onMinutes = { [weak self] minutes in
            self?.actions.quickProtect(minutes)
        }

        permissionCard.onOpen = { [weak self] in
            self?.actions.permissions()
        }

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        let contentViews: [NSView] = [
            hero,
            quickPanel,
            permissionCard,
        ]
        for view in contentViews {
            contentStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let document = DashboardFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let footerDivider = CurtainDividerView()
        let settingsButton = CurtainButton(
            title: "设置",
            symbol: "slider.horizontal.3",
            style: .secondary,
            target: self,
            action: #selector(settingsClicked)
        )
        versionLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        versionLabel.textColor = CurtainTheme.tertiaryInk
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = CurtainTheme.stack(
            [settingsButton, footerSpacer, versionLabel],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )

        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(footerDivider)
        root.addSubview(footer)
        header.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.subviews[0].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            root.subviews[0].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.subviews[0].topAnchor.constraint(equalTo: root.topAnchor),
            root.subviews[0].bottomAnchor.constraint(equalTo: root.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -12),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footerDivider.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        view = root
    }

    func start() {
        update()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var preferredPopoverSize: NSSize {
        guard let snapshot else {
            return NSSize(width: 420, height: 560)
        }
        let base: CGFloat = snapshot.curtainState.isOn ? 450 : 540
        let missingPermissions: CGFloat = snapshot.permissionsReady ? 0 : 84
        return NSSize(width: 420, height: base + missingPermissions)
    }

    private func update() {
        let snapshot = provider()
        self.snapshot = snapshot
        statusPill.update(text: stateLabel(snapshot), color: stateColor(snapshot))
        hero.update(snapshot: snapshot)
        quickPanel.update(snapshot: snapshot)
        permissionCard.isHidden = snapshot.permissionsReady
        versionLabel.stringValue = "v\(snapshot.version)"
        onPreferredSizeChange?()
    }

    private func stateLabel(_ snapshot: DashboardSnapshot) -> String {
        switch snapshot.curtainState {
        case .idle: return snapshot.recording ? "录制中" : "待命"
        case .active: return "已遮挡"
        case .authenticating: return "验证中"
        }
    }

    private func stateColor(_ snapshot: DashboardSnapshot) -> NSColor {
        switch snapshot.curtainState {
        case .idle: return snapshot.recording ? CurtainTheme.danger : CurtainTheme.secondaryInk
        case .active: return CurtainTheme.accent
        case .authenticating: return CurtainTheme.warning
        }
    }

    @objc private func quitClicked() {
        actions.quit()
    }

    @objc private func settingsClicked() {
        actions.settings()
    }

}

private final class DashboardHeroView: NSView {
    var onToggle: (() -> Void)?
    var onStopRecording: (() -> Void)?

    private let gradient = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let eyebrow = NSTextField(labelWithString: "")
    private let recordLabel = NSTextField(labelWithString: "●  录制中")
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let primaryMetric = DashboardHeroMetric(label: "快捷键")
    private let toggleButton = CurtainButton(
        title: "开启幕帘",
        symbol: "rectangle.fill",
        style: .primary,
        target: nil,
        action: nil
    )
    private let stopButton = CurtainButton(
        title: "结束录制",
        symbol: "stop.fill",
        style: .danger,
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        gradient.colors = [
            NSColor(srgbRed: 0.105, green: 0.126, blue: 0.155, alpha: 1).cgColor,
            NSColor(srgbRed: 0.031, green: 0.039, blue: 0.052, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        glow.type = .radial
        glow.colors = [
            CurtainTheme.accent.withAlphaComponent(0.22).cgColor,
            CurtainTheme.accent.withAlphaComponent(0).cgColor,
        ]
        glow.startPoint = CGPoint(x: 0.78, y: 0.9)
        glow.endPoint = CGPoint(x: 1.4, y: 0)
        layer?.addSublayer(glow)

        eyebrow.font = .systemFont(ofSize: 9, weight: .bold)
        eyebrow.textColor = CurtainTheme.accent
        recordLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        recordLabel.textColor = CurtainTheme.danger
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textColor = .white
        detail.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        detail.textColor = NSColor.white.withAlphaComponent(0.56)
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let topRow = CurtainTheme.stack(
            [eyebrow, topSpacer, recordLabel],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.isHidden = true
        toggleButton.target = self
        toggleButton.action = #selector(toggleClicked)
        let buttonRow = CurtainTheme.stack(
            [toggleButton, stopButton],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        toggleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = CurtainTheme.stack(
            [topRow, title, detail, primaryMetric, buttonRow],
            spacing: 6
        )
        content.setCustomSpacing(12, after: detail)
        content.setCustomSpacing(14, after: primaryMetric)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            topRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            primaryMetric.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        glow.frame = bounds
    }

    func update(snapshot: DashboardSnapshot) {
        switch snapshot.curtainState {
        case .idle:
            eyebrow.stringValue = "READY"
            title.stringValue = "幕帘待命"
            detail.stringValue = "按 \(snapshot.hotkey) 开启"
            toggleButton.setTitle("开启幕帘")
            toggleButton.image = NSImage(
                systemSymbolName: "rectangle.fill",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = true
        case .active:
            eyebrow.stringValue = snapshot.scene.map {
                "VISIBILITY OFF · \($0.title)"
            } ?? "VISIBILITY OFF"
            title.stringValue = "幕帘已遮挡"
            let scenePrefix = snapshot.scene.map { "\($0.title) · " } ?? ""
            detail.stringValue = "\(scenePrefix)双击 Esc 或按 \(snapshot.hotkey) 解除"
            toggleButton.setTitle("解除幕帘")
            toggleButton.image = NSImage(
                systemSymbolName: "touchid",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = true
        case .authenticating:
            eyebrow.stringValue = snapshot.scene.map {
                "TOUCH ID · \($0.title)"
            } ?? "TOUCH ID"
            title.stringValue = "等待 Touch ID"
            let scenePrefix = snapshot.scene.map { "\($0.title) · " } ?? ""
            detail.stringValue = "\(scenePrefix)再按一次 Esc 取消验证"
            toggleButton.setTitle("等待 Touch ID")
            toggleButton.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = false
        }
        recordLabel.isHidden = !snapshot.recording
        stopButton.isHidden = !snapshot.recording
        primaryMetric.update(
            value: snapshot.curtainState.isOn ? snapshot.elapsed : snapshot.hotkey,
            label: snapshot.curtainState.isOn ? "已保护" : "快捷键"
        )
    }

    @objc private func toggleClicked() {
        onToggle?()
    }

    @objc private func stopClicked() {
        onStopRecording?()
    }
}

private final class DashboardHeroMetric: NSView {
    private let valueLabel = NSTextField(labelWithString: "—")
    private let nameLabel = NSTextField(labelWithString: "")

    init(label: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        valueLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1
        nameLabel.stringValue = label
        nameLabel.font = .systemFont(ofSize: 8.5)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        let stack = CurtainTheme.stack([valueLabel, nameLabel], spacing: 2)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(value: String, label: String) {
        valueLabel.stringValue = value
        nameLabel.stringValue = label
    }
}

private final class DashboardPermissionCard: NSView {
    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        let icon = CurtainIconTile(
            symbol: "exclamationmark.shield.fill",
            color: CurtainTheme.warning,
            size: 30
        )
        let title = CurtainTheme.label(
            "系统权限还不完整",
            size: 11,
            weight: .semibold
        )
        let detail = CurtainTheme.label(
            "打开系统设置，把 Curtain 拖进对应列表。",
            size: 9.5,
            color: CurtainTheme.secondaryInk
        )
        let textStack = CurtainTheme.stack([title, detail], spacing: 2)
        let button = CurtainButton(
            title: "打开设置",
            style: .secondary,
            target: self,
            action: #selector(openClicked)
        )
        let row = CurtainTheme.stack(
            [icon, textStack, button],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CurtainTheme.warning.withAlphaComponent(0.09).cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = CurtainTheme.warning.withAlphaComponent(0.18).cgColor
        }
    }

    @objc private func openClicked() {
        onOpen?()
    }
}

private final class DashboardQuickPanel: NSView {
    var onScene: ((CurtainScene) -> Void)?
    var onMinutes: ((Int) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let sceneRow = NSStackView()
    private let minuteRow = NSStackView()
    private var sceneTiles: [CurtainScene: DashboardSceneTile] = [:]
    private var minuteButtons: [CurtainButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let card = CurtainCardView(
            padding: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = CurtainTheme.ink
        detailLabel.font = .systemFont(ofSize: 9.5)
        detailLabel.textColor = CurtainTheme.tertiaryInk
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleRow = CurtainTheme.stack(
            [titleLabel, spacer, detailLabel],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )

        sceneRow.orientation = .horizontal
        sceneRow.distribution = .fillEqually
        sceneRow.spacing = 8
        sceneRow.alignment = .centerY
        for scene in CurtainScene.allCases {
            let tile = DashboardSceneTile(scene: scene)
            tile.onClick = { [weak self] in
                self?.onScene?(scene)
            }
            sceneTiles[scene] = tile
            sceneRow.addArrangedSubview(tile)
            tile.heightAnchor.constraint(equalToConstant: 74).isActive = true
        }

        minuteRow.orientation = .horizontal
        minuteRow.distribution = .fillEqually
        minuteRow.spacing = 7
        minuteRow.alignment = .centerY
        for minutes in [30, 60, 120, 0] {
            let button = CurtainButton(
                title: minutes == 0 ? "不限时" : "\(minutes) 分钟",
                style: .secondary,
                target: self,
                action: #selector(minuteClicked(_:))
            )
            button.tag = minutes
            minuteButtons.append(button)
            minuteRow.addArrangedSubview(button)
        }

        let stack = CurtainTheme.stack(
            [titleRow, sceneRow, minuteRow],
            spacing: 10
        )
        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sceneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            minuteRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(snapshot: DashboardSnapshot) {
        let active = snapshot.curtainState.isOn
        if active {
            titleLabel.stringValue = "延长保护"
            detailLabel.stringValue = snapshot.protectionRemaining.map {
                "剩余 \($0)"
            } ?? "当前不限时"
            sceneRow.isHidden = true
            for (index, title) in ["+30 分", "+60 分", "+120 分", "不限时"].enumerated() {
                minuteButtons[index].setTitle(title)
            }
        } else {
            titleLabel.stringValue = "一键保护"
            detailLabel.stringValue = "选择场景，或直接按时长起幕"
            sceneRow.isHidden = false
            for scene in CurtainScene.allCases {
                sceneTiles[scene]?.update(
                    minutes: snapshot.sceneMinutes[scene]
                        ?? scene.defaultProtectionMinutes,
                    presentationLabel: snapshot.scenePresentationLabels[scene]
                        ?? snapshot.presentationLabel,
                    hotkey: snapshot.sceneHotkeys[scene] ?? ""
                )
            }
            for (index, minutes) in [30, 60, 120, 0].enumerated() {
                minuteButtons[index].setTitle(
                    minutes == 0 ? "不限时" : "\(minutes) 分钟"
                )
            }
        }
        let canAct = snapshot.curtainState != .authenticating
        minuteButtons.forEach { $0.isEnabled = canAct }
    }

    @objc private func minuteClicked(_ sender: NSButton) {
        onMinutes?(sender.tag)
    }
}

private final class DashboardSceneTile: NSButton {
    var onClick: (() -> Void)?

    private let scene: CurtainScene
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var hovered = false

    init(scene: CurtainScene) {
        self.scene = scene
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        title = ""
        imagePosition = .noImage
        target = self
        action = #selector(clicked)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 0.7

        iconView.image = NSImage(
            systemSymbolName: scene.symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = tint
        titleLabel.stringValue = scene.title
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = CurtainTheme.ink
        durationLabel.font = .systemFont(ofSize: 8.5)
        durationLabel.textColor = CurtainTheme.tertiaryInk
        durationLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.font = .monospacedSystemFont(
            ofSize: 7.5,
            weight: .medium
        )
        shortcutLabel.textColor = CurtainTheme.tertiaryInk
        shortcutLabel.alignment = .right

        let titleSpacer = NSView()
        titleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleRow = CurtainTheme.stack(
            [titleLabel, titleSpacer, shortcutLabel],
            orientation: .horizontal,
            spacing: 3,
            alignment: .centerY
        )

        let stack = CurtainTheme.stack(
            [iconView, titleRow, durationLabel],
            spacing: 3
        )
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(minutes: Int, presentationLabel: String, hotkey: String) {
        durationLabel.stringValue = "\(CurtainScene.durationText(minutes: minutes))"
            + " · \(presentationLabel)"
        shortcutLabel.stringValue = hotkey
        shortcutLabel.isHidden = hotkey.isEmpty
    }

    private var tint: NSColor {
        switch scene {
        case .away: return CurtainTheme.accent
        case .meeting: return CurtainTheme.warning
        case .guest: return CurtainTheme.success
        case .focus: return CurtainTheme.focus
        }
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovered
                ? tint.withAlphaComponent(0.13)
                : CurtainTheme.field
            ).cgColor
            layer?.borderColor = (hovered
                ? tint.withAlphaComponent(0.34)
                : CurtainTheme.border
            ).cgColor
        }
    }

    @objc private func clicked() {
        onClick?()
    }
}

private final class DashboardFlippedView: NSView {
    override var isFlipped: Bool { true }
}
