import AppKit
import CurtainKit

extension SettingsWindowController {
    func makeGeneralPage() -> NSView {
        let colorControls = NSStackView()
        colorControls.orientation = .horizontal
        colorControls.spacing = 8
        colorWell.color = nsColor(from: config.curtainColor)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 54),
            colorWell.heightAnchor.constraint(equalToConstant: 28),
        ])
        let resetColor = CurtainButton(
            title: "恢复黑色",
            style: .secondary,
            target: self,
            action: #selector(resetColor)
        )
        colorControls.addArrangedSubview(colorWell)
        colorControls.addArrangedSubview(resetColor)

        hotkeyButton.onCapture = { [weak self] binding in
            self?.diagnosticsHotkeyValue.stringValue = HotkeyPolicy.displayString(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers
            )
        }
        hotkeyButton.translatesAutoresizingMaskIntoConstraints = false
        hotkeyButton.widthAnchor.constraint(equalToConstant: 124).isActive = true
        hotkeyButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        for control in [hideCursorSwitch, clamshellSwitch, presentationSwitch] {
            control.controlSize = .small
            control.translatesAutoresizingMaskIntoConstraints = false
        }

        let rows: [NSView] = [
            CurtainSettingRow(
                title: "双击 Esc 解除",
                detail: "两次物理 Esc 落在这个窗口内时，直接请求 Touch ID。",
                control: doubleField
            ),
            CurtainSettingRow(
                title: "长按 Esc 兜底",
                detail: "按住 Esc 达到这个时长后请求 Touch ID。",
                control: holdField
            ),
            CurtainSettingRow(
                title: "起幕 / 撤幕快捷键",
                detail: "必须包含 Control、Option 或 Command 中的至少一个。",
                control: hotkeyButton
            ),
            CurtainSettingRow(
                title: "默认幕帘颜色",
                detail: "默认黑色；输出层纯色仍然不会出现在 Agent 截图里。",
                control: colorControls
            ),
            CurtainSettingRow(
                title: "隐藏鼠标指针",
                detail: "幕帘期间不让指针出现在屏幕上，Agent 截图也不受影响。",
                control: hideCursorSwitch
            ),
            CurtainSettingRow(
                title: "合盖继续运行",
                detail: "申请系统防休眠；外接屏在位时通常可合盖继续，最终由 macOS 电源策略决定。",
                control: clamshellSwitch
            ),
        ]
        let mainCard = card(containing: rows)

        let touchIcon = CurtainIconTile(
            symbol: "touchid",
            color: CurtainTheme.accent,
            size: 32
        )
        let noteTitle = CurtainTheme.label(
            "Touch ID 是唯一正常出口",
            size: 12,
            weight: .semibold
        )
        let noteText = CurtainTheme.label(
            "密码不会作为备用出口。硬件不可用时，Curtain 会失败撤幕，避免把人锁在黑屏里。",
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        let noteStack = CurtainTheme.stack([noteTitle, noteText], spacing: 3)
        let noteRow = CurtainTheme.stack(
            [touchIcon, noteStack],
            orientation: .horizontal,
            spacing: 14,
            alignment: .top
        )
        let noteCard = CurtainCardView(padding: NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
        noteCard.contentView.addSubview(noteRow)
        pin(noteRow, to: noteCard.contentView)

        return page(views: [mainCard, noteCard], spacing: CurtainTheme.sectionSpacing)
    }
}
