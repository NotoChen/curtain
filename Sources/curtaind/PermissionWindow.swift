import AppKit
import CoreGraphics
import CurtainKit

enum PermissionPane {
    case accessibility
    case screenRecording
}

final class PermissionStatusModel {
    private(set) var hasAccessibility = Permissions.hasAccessibility()
    private(set) var hasScreenRecording = Permissions.hasScreenRecording()
    var onChange: (() -> Void)?

    var allGranted: Bool {
        hasAccessibility && hasScreenRecording
    }

    var nextMissing: PermissionPane? {
        if !hasAccessibility { return .accessibility }
        if !hasScreenRecording { return .screenRecording }
        return nil
    }

    func refresh() {
        let accessibility = Permissions.hasAccessibility()
        let screenRecording = Permissions.hasScreenRecording()
        guard accessibility != hasAccessibility || screenRecording != hasScreenRecording else {
            return
        }
        hasAccessibility = accessibility
        hasScreenRecording = screenRecording
        onChange?()
    }
}

/// A lightweight authorization guide. It deliberately has no second large
/// window: System Settings is the source of truth, and the floating companion
/// exists only to make Curtain.app draggable into the right privacy list.
final class PermissionGuideController {
    var onAllGranted: (() -> Void)?

    private let model = PermissionStatusModel()
    private var companion: PermissionCompanionWindowController?
    private var timer: Timer?
    private var reportedGranted = false

    func present(openSettings: Bool, pane: PermissionPane? = nil) {
        showCompanion()
        if openSettings, let target = pane ?? model.nextMissing {
            open(target)
        }
        startPolling()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        companion?.window?.orderOut(nil)
    }

    private func showCompanion() {
        if companion == nil {
            let controller = PermissionCompanionWindowController(
                model: model,
                onOpen: { [weak self] pane in
                    self?.open(pane)
                }
            )
            model.onChange = { [weak self] in
                self?.refresh()
            }
            companion = controller
        }
        companion?.show()
    }

    private func open(_ pane: PermissionPane) {
        switch pane {
        case .accessibility:
            Permissions.openAccessibilitySettings()
        case .screenRecording:
            Permissions.openScreenRecordingSettings()
        }
        showCompanion()
        startPolling()
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        model.refresh()
        companion?.render()
        if model.allGranted {
            guard !reportedGranted else { return }
            reportedGranted = true
            companion?.complete()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.stop()
                self?.onAllGranted?()
            }
        } else {
            reportedGranted = false
        }
    }
}

final class PermissionCompanionWindowController: NSWindowController, NSWindowDelegate {
    private let model: PermissionStatusModel
    private let onOpen: (PermissionPane) -> Void
    private let accessibilityRow: CompanionStatusRow
    private let screenRecordingRow: CompanionStatusRow
    private let dragView: AppBundleDragView
    private let instructionLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(
        labelWithString: "拖动后会自动检测；如果列表里已有旧版 Curtain，先移除旧项，再拖入当前版本。"
    )
    private let actionButton: CurtainButton
    private let successView: NSView
    private var completed = false
    private var positioningTimer: Timer?
    private var lastSettingsFrame: NSRect?
    private var hasPositioned = false

    init(model: PermissionStatusModel, onOpen: @escaping (PermissionPane) -> Void) {
        self.model = model
        self.onOpen = onOpen
        let appURL = Self.appURL
        dragView = AppBundleDragView(appURL: appURL)
        accessibilityRow = CompanionStatusRow(
            symbol: "keyboard",
            title: "设备控制和数据访问",
            granted: false
        )
        screenRecordingRow = CompanionStatusRow(
            symbol: "rectangle.dashed.badge.record",
            title: "录屏与系统录音",
            granted: false
        )
        actionButton = CurtainButton(
            title: "打开系统设置",
            symbol: "gearshape",
            style: .primary,
            target: nil,
            action: nil
        )

        let checkIcon = NSImageView()
        checkIcon.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "授权完成"
        )
        checkIcon.contentTintColor = CurtainTheme.success
        checkIcon.imageScaling = .scaleProportionallyDown
        let checkLabel = CurtainTheme.label(
            "两项权限已就绪",
            size: 12,
            weight: .semibold,
            color: CurtainTheme.success
        )
        let successStack = CurtainTheme.stack(
            [checkIcon, checkLabel],
            orientation: .horizontal,
            spacing: 7,
            alignment: .centerY
        )
        successStack.translatesAutoresizingMaskIntoConstraints = false
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkIcon.widthAnchor.constraint(equalToConstant: 15),
            checkIcon.heightAnchor.constraint(equalToConstant: 15),
        ])
        successView = NSView()
        successView.wantsLayer = true
        successView.layer?.cornerRadius = 10
        successView.layer?.backgroundColor = CurtainTheme.success.withAlphaComponent(0.12).cgColor
        successView.addSubview(successStack)
        NSLayoutConstraint.activate([
            successStack.centerXAnchor.constraint(equalTo: successView.centerXAnchor),
            successStack.centerYAnchor.constraint(equalTo: successView.centerYAnchor),
            successView.heightAnchor.constraint(equalToConstant: 36),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 548),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        CurtainWindowChrome.apply(to: window, title: "Curtain 授权")
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        super.init(window: window)
        window.delegate = self
        actionButton.target = self
        actionButton.action = #selector(openNext)
        buildUI(appURL: appURL)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible != true {
            hasPositioned = false
            lastSettingsFrame = nil
            positionWindow()
        }
        window?.orderFrontRegardless()
        startPositioning()
    }

    func complete() {
        guard !completed else { return }
        completed = true
        stopPositioning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    func render() {
        accessibilityRow.setGranted(model.hasAccessibility)
        screenRecordingRow.setGranted(model.hasScreenRecording)
        successView.isHidden = !model.allGranted
        actionButton.isHidden = model.allGranted
        if model.allGranted {
            instructionLabel.stringValue = "授权完成"
            instructionLabel.textColor = CurtainTheme.success
        } else if !model.hasAccessibility {
            instructionLabel.stringValue = "拖进「设备控制和数据访问」"
            instructionLabel.textColor = CurtainTheme.ink
            actionButton.setTitle("打开辅助功能设置")
        } else {
            instructionLabel.stringValue = "再拖进「录屏与系统录音」"
            instructionLabel.textColor = CurtainTheme.ink
            actionButton.setTitle("打开录屏设置")
        }
    }

    private func buildUI(appURL: URL) {
        guard let window else { return }
        let root = NSView()
        root.addSubview(CurtainBackdropView())
        root.subviews[0].translatesAutoresizingMaskIntoConstraints = false

        let brand = CurtainBrandIconView(size: 28)
        let title = CurtainTheme.label("拖拽授权", size: 13, weight: .semibold)
        let subtitle = CurtainTheme.label(
            "窗口会跟随系统设置",
            size: 9.5,
            color: CurtainTheme.secondaryInk
        )
        let titleStack = CurtainTheme.stack([title, subtitle], spacing: 1)
        let closeButton = CurtainIconButton(
            symbol: "xmark",
            accessibilityLabel: "关闭授权浮窗",
            target: self,
            action: #selector(closeClicked)
        )
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = CurtainTheme.stack(
            [brand, titleStack, headerSpacer, closeButton],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )

        let dashedCard = DashedBorderView()
        let dragStack = CurtainTheme.stack(
            [dragView, instructionLabel],
            spacing: 8,
            alignment: .centerX
        )
        instructionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        instructionLabel.alignment = .center
        let dragHint = CurtainTheme.label(
            "按住图标，拖到系统设置的 app 列表",
            size: 9.5,
            color: CurtainTheme.tertiaryInk
        )
        dragHint.alignment = .center
        let dragCopy = CurtainTheme.stack(
            [dragStack, dragHint],
            spacing: 4,
            alignment: .centerX
        )
        dashedCard.addSubview(dragCopy)
        dragCopy.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dragView.widthAnchor.constraint(equalToConstant: 92),
            dragView.heightAnchor.constraint(equalToConstant: 92),
            dragCopy.centerXAnchor.constraint(equalTo: dashedCard.centerXAnchor),
            dragCopy.centerYAnchor.constraint(equalTo: dashedCard.centerYAnchor),
            dragCopy.leadingAnchor.constraint(greaterThanOrEqualTo: dashedCard.leadingAnchor, constant: 12),
            dragCopy.trailingAnchor.constraint(lessThanOrEqualTo: dashedCard.trailingAnchor, constant: -12),
            dashedCard.heightAnchor.constraint(equalToConstant: 170),
        ])

        let statusRows = NSStackView()
        statusRows.orientation = .vertical
        statusRows.spacing = 0
        statusRows.alignment = .leading
        let statusDivider = CurtainDividerView()
        statusRows.addArrangedSubview(accessibilityRow)
        statusRows.addArrangedSubview(statusDivider)
        statusRows.addArrangedSubview(screenRecordingRow)
        accessibilityRow.widthAnchor.constraint(equalTo: statusRows.widthAnchor).isActive = true
        statusDivider.widthAnchor.constraint(equalTo: statusRows.widthAnchor).isActive = true
        screenRecordingRow.widthAnchor.constraint(equalTo: statusRows.widthAnchor).isActive = true
        let statusCard = CurtainCardView(
            padding: NSEdgeInsets(top: 6, left: 15, bottom: 6, right: 15)
        )
        statusCard.contentView.addSubview(statusRows)
        pin(statusRows, to: statusCard.contentView)

        noteLabel.font = .systemFont(ofSize: 9)
        noteLabel.textColor = CurtainTheme.tertiaryInk
        noteLabel.maximumNumberOfLines = 2
        noteLabel.lineBreakMode = .byWordWrapping

        let noteContainer = NSView()
        noteContainer.addSubview(noteLabel)
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            noteLabel.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -12),
            noteLabel.topAnchor.constraint(equalTo: noteContainer.topAnchor),
            noteLabel.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor),
        ])

        let actionContainer = NSView()
        actionContainer.addSubview(actionButton)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: 10),
            actionButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor, constant: -10),
            actionButton.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),
        ])

        let content = CurtainTheme.stack(
            [header, dashedCard, statusCard, actionContainer, successView, noteContainer],
            spacing: 14
        )
        content.setCustomSpacing(12, after: statusCard)
        content.setCustomSpacing(12, after: actionContainer)
        header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        dashedCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        statusCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        actionContainer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        successView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        noteContainer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        root.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.subviews[0].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            root.subviews[0].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.subviews[0].topAnchor.constraint(equalTo: root.topAnchor),
            root.subviews[0].bottomAnchor.constraint(equalTo: root.bottomAnchor),

            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 38),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
        ])
        window.contentView = root
    }

    private func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    private func positionWindow() {
        guard let window else { return }
        if let settingsFrame = systemSettingsFrame() {
            guard settingsFrame != lastSettingsFrame || !hasPositioned else { return }
            let visible = screen(containing: settingsFrame).visibleFrame
            let size = window.frame.size
            let gap: CGFloat = 18
            var x = settingsFrame.maxX + gap
            if x + size.width > visible.maxX {
                x = settingsFrame.minX - gap - size.width
            }
            if x < visible.minX {
                x = visible.maxX - size.width - 20
            }
            let y = min(
                max(settingsFrame.maxY - size.height - 22, visible.minY + 20),
                visible.maxY - size.height - 20
            )
            window.setFrameOrigin(NSPoint(x: x, y: y))
            lastSettingsFrame = settingsFrame
            hasPositioned = true
        } else if !hasPositioned {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let visible = screen?.visibleFrame else {
                CurtainWindowChrome.centerOnActiveScreen(window)
                hasPositioned = true
                return
            }
            let size = window.frame.size
            window.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - size.width - 26,
                    y: visible.minY + max(26, (visible.height - size.height) * 0.42)
                )
            )
            hasPositioned = true
        }
    }

    private func startPositioning() {
        guard positioningTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.positionWindow()
        }
        RunLoop.main.add(timer, forMode: .common)
        positioningTimer = timer
    }

    private func stopPositioning() {
        positioningTimer?.invalidate()
        positioningTimer = nil
    }

    private func systemSettingsFrame() -> NSRect? {
        let bundleIDs = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        let pids = Set(bundleIDs.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
                .map(\.processIdentifier)
        })
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var best: CGRect?
        for item in windows {
            let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let owner = item[kCGWindowOwnerName as String] as? String
            let isSettings = pid.map(pids.contains) == true
                || owner == "System Settings"
                || owner == "系统设置"
            guard isSettings else { continue }
            guard (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= 320, height >= 240 else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            if best == nil || rect.width * rect.height > (best?.width ?? 0) * (best?.height ?? 0) {
                best = rect
            }
        }
        guard let bounds = best else { return nil }
        let reference = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let reference else { return nil }
        return NSRect(
            x: bounds.origin.x,
            y: reference.frame.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func screen(containing frame: NSRect) -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    @objc private func openNext() {
        if let next = model.nextMissing {
            onOpen(next)
        }
    }

    @objc private func closeClicked() {
        stopPositioning()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopPositioning()
    }

    private static var appURL: URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension.lowercased() == "app" {
            return bundle
        }
        let installed = URL(fileURLWithPath: "/Applications/Curtain.app")
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return bundle
    }
}

private final class CompanionStatusRow: NSView {
    private let tile: CurtainIconTile
    private let pill: CurtainStatusPillView

    init(symbol: String, title: String, granted: Bool) {
        tile = CurtainIconTile(
            symbol: symbol,
            color: granted ? CurtainTheme.success : CurtainTheme.secondaryInk,
            size: 24
        )
        pill = CurtainStatusPillView(
            text: granted ? "已授权" : "未授权",
            color: granted ? CurtainTheme.success : CurtainTheme.warning
        )
        super.init(frame: .zero)
        let titleLabel = CurtainTheme.label(title, size: 10.5)
        let row = CurtainTheme.stack(
            [tile, titleLabel, pill],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
        setGranted(granted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setGranted(_ granted: Bool) {
        tile.setColor(granted ? CurtainTheme.success : CurtainTheme.secondaryInk)
        pill.update(
            text: granted ? "已授权" : "未授权",
            color: granted ? CurtainTheme.success : CurtainTheme.warning
        )
    }
}

private final class DashedBorderView: NSView {
    private let border = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = CurtainTheme.field.cgColor
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = CurtainTheme.accent.withAlphaComponent(0.34).cgColor
        border.lineWidth = 1
        border.lineDashPattern = [5, 5]
        layer?.addSublayer(border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 15,
            cornerHeight: 15,
            transform: nil
        )
        layer?.backgroundColor = CurtainTheme.field.cgColor
    }
}

private final class AppBundleDragView: NSView, NSDraggingSource {
    private let appURL: URL
    private let appIcon: NSImage
    private let iconView = NSImageView()
    private var mouseDownEvent: NSEvent?
    private var dragging = false

    init(appURL: URL) {
        self.appURL = appURL
        let iconURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AppIcon.icns")
        self.appIcon = CurtainAppIcon.image(at: iconURL, pointSize: 92)
            ?? NSWorkspace.shared.icon(forFile: appURL.path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        toolTip = "按住并拖到系统设置的隐私列表"
        iconView.image = appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragging = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let mouseDownEvent else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: appIcon)
        beginDraggingSession(
            with: [item],
            event: mouseDownEvent,
            source: self
        )
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
