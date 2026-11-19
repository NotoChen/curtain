import AppKit
import CurtainKit

extension SettingsWindowController {
    func makeAutomationPage() -> NSView {
        for control in [
            idleSwitch,
            scheduleSwitch,
            scheduleAutoExitSwitch,
        ] {
            control.controlSize = .small
            control.translatesAutoresizingMaskIntoConstraints = false
        }
        idleSwitch.target = self
        idleSwitch.action = #selector(automationToggled)
        scheduleSwitch.target = self
        scheduleSwitch.action = #selector(automationToggled)
        scheduleAutoExitSwitch.target = self
        scheduleAutoExitSwitch.action = #selector(automationToggled)

        for picker in [scheduleStartPicker, scheduleEndPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.controlSize = .small
            picker.translatesAutoresizingMaskIntoConstraints = false
            picker.widthAnchor.constraint(equalToConstant: 108).isActive = true
        }
        let timeControls = CurtainTheme.stack(
            [
                CurtainTheme.label("从", size: 10.5, color: CurtainTheme.secondaryInk),
                scheduleStartPicker,
                CurtainTheme.label("到", size: 10.5, color: CurtainTheme.secondaryInk),
                scheduleEndPicker,
            ],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )

        weekdayButtons = ["一", "二", "三", "四", "五", "六", "日"].enumerated().map {
            index, title in
            let button = NSButton(title: title, target: nil, action: nil)
            button.tag = index
            button.setButtonType(.toggle)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            return button
        }
        let weekdayControls = CurtainTheme.stack(
            weekdayButtons,
            orientation: .horizontal,
            spacing: 5,
            alignment: .centerY
        )

        let rows: [NSView] = [
            CurtainSettingRow(
                title: "空闲自动起幕",
                detail: "系统物理输入空闲达到阈值后自动升起幕帘。",
                control: idleSwitch
            ),
            CurtainSettingRow(
                title: "空闲阈值",
                detail: "只触发一次；用户重新操作后会重新武装。",
                control: idleMinutesField
            ),
            CurtainSettingRow(
                title: "每日定时保护",
                detail: "进入选中星期的保护时段时自动起幕。",
                control: scheduleSwitch
            ),
            CurtainSettingRow(
                title: "保护时段",
                detail: "支持跨午夜；开始和结束相同表示全天。",
                control: timeControls
            ),
            CurtainSettingRow(
                title: "生效星期",
                detail: "周一至周日可多选；启用定时时至少选择一天。",
                control: weekdayControls
            ),
            CurtainSettingRow(
                title: "时段结束后验证退出",
                detail: "默认关闭。开启后只发起 Touch ID，不会无声露出桌面。",
                control: scheduleAutoExitSwitch
            ),
            CurtainSettingRow(
                title: "默认保护时长",
                detail: "到时发起 Touch ID；0 表示保护到手动验证。",
                control: protectionMinutesField
            ),
        ]
        let settingsCard = card(containing: rows)

        let noteIcon = CurtainIconTile(
            symbol: "lock.shield",
            color: CurtainTheme.accent,
            size: 32
        )
        let noteTitle = CurtainTheme.label(
            "任何自动路径都不会绕过 Touch ID",
            size: 12,
            weight: .semibold
        )
        let noteText = CurtainTheme.label(
            "空闲、定时和倒计时只负责起幕或发起验证。唯一正常出口仍是 Touch ID；系统睡眠、权限失效和覆盖失败会失败撤幕。",
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        let noteStack = CurtainTheme.stack([noteTitle, noteText], spacing: 3)
        let noteRow = CurtainTheme.stack(
            [noteIcon, noteStack],
            orientation: .horizontal,
            spacing: 14,
            alignment: .top
        )
        let noteCard = CurtainCardView(
            padding: NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        )
        noteCard.contentView.addSubview(noteRow)
        pin(noteRow, to: noteCard.contentView)
        updateAutomationControls()

        return page(
            views: [settingsCard, noteCard],
            spacing: CurtainTheme.sectionSpacing
        )
    }

    func updateAutomationControls() {
        let idleEnabled = idleSwitch.state == .on
        idleMinutesField.isEnabled = idleEnabled
        let scheduleEnabled = scheduleSwitch.state == .on
        scheduleStartPicker.isEnabled = scheduleEnabled
        scheduleEndPicker.isEnabled = scheduleEnabled
        scheduleAutoExitSwitch.isEnabled = scheduleEnabled
        weekdayButtons.forEach { $0.isEnabled = scheduleEnabled }
    }

    @objc func automationToggled() {
        updateAutomationControls()
    }

    func date(fromMinutes minutes: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .minute,
            value: min(1439, max(0, minutes)),
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
    }

    func minutes(from picker: NSDatePicker) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: picker.dateValue
        )
        return min(
            1439,
            max(0, (components.hour ?? 0) * 60 + (components.minute ?? 0))
        )
    }
}
