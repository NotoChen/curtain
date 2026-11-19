import AppKit
import CurtainKit

extension AppDelegate {
    // MARK: - 菜单栏

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item

        statusPopover = StatusPopoverController(
            provider: { [weak self] in
                self?.dashboardSnapshot() ?? DashboardSnapshot(
                    curtainState: .idle,
                    recording: false,
                    hotkey: "—",
                    elapsed: "00:00",
                    scene: nil,
                    sceneMinutes: Dictionary(
                        uniqueKeysWithValues: CurtainScene.allCases.map {
                            ($0, $0.defaultProtectionMinutes)
                        }
                    ),
                    scenePresentationLabels: [:],
                    sceneHotkeys: [:],
                    protectionRemaining: nil,
                    presentationLabel: "黑幕",
                    hasAccessibility: false,
                    hasScreenRecording: false,
                    version: "dev"
                )
            },
            actions: DashboardActions(
                toggle: { [weak self] in
                    self?.toggleFromDashboard()
                },
                activateScene: { [weak self] scene in
                    self?.activateScene(scene)
                },
                quickProtect: { [weak self] minutes in
                    self?.quickProtect(minutes: minutes)
                },
                stopRecording: { [weak self] in
                    self?.menuStopRecording()
                },
                permissions: { [weak self] in
                    self?.showPermissionGuide(openSettings: true)
                },
                settings: { [weak self] in
                    self?.showSettings()
                },
                quit: { [weak self] in
                    self?.menuQuit()
                }
            )
        )
        updateStatusItem()
    }

    func updateStatusItem() {
        let apply = { [weak self] in
            guard let self else { return }
            let tooltip: String
            if self.authPending {
                tooltip = "Curtain：等待 Touch ID"
            } else if self.curtainOn {
                tooltip = "Curtain：幕帘已开启"
            } else if self.recorder.isRecording {
                tooltip = "Curtain：正在录制"
            } else {
                tooltip = "Curtain：待命"
            }
            let image = CurtainGlyph.image(
                size: 18,
                curtainOn: self.curtainOn,
                authenticating: self.authPending,
                recording: self.recorder.isRecording
            )
            image.accessibilityDescription = tooltip
            self.statusItem?.button?.image = image
            self.statusItem?.button?.imagePosition = .imageOnly
            self.statusItem?.button?.toolTip = tooltip
            self.statusItem?.button?.setAccessibilityLabel(tooltip)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    @objc func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        statusPopover?.toggle(relativeTo: button)
    }

    func toggleFromDashboard() {
        if state == .active {
            requestExit()
        } else if state == .idle {
            startCurtain()
        }
    }

    func activateScene(_ scene: CurtainScene) {
        guard state == .idle else { return }
        startCurtain(
            trigger: .scene,
            protectionMinutes: config.protectionMinutes(for: scene),
            scene: scene
        )
    }

    func handleSceneHotkey(_ scene: CurtainScene) {
        guard state == .idle else { return }
        activateScene(scene)
    }

    func quickProtect(minutes: Int) {
        switch state {
        case .idle:
            startCurtain(
                trigger: .manual,
                protectionMinutes: min(1440, max(0, minutes))
            )
        case .active:
            if minutes == 0 {
                clearProtection()
            } else {
                extendProtection(by: minutes)
            }
        case .authenticating:
            break
        }
    }

    func extendProtection(by minutes: Int) {
        guard curtainOn else { return }
        let bounded = min(1440, max(1, minutes))
        let base = max(Date(), protectionDeadline ?? Date())
        let deadline = base.addingTimeInterval(TimeInterval(bounded * 60))
        protectionItem?.cancel()
        protectionDeadline = deadline
        protectionPrompted = false
        sessionProtectionMinutes = max(
            1,
            Int(ceil(deadline.timeIntervalSinceNow / 60))
        )
        let item = DispatchWorkItem { [weak self] in
            self?.protectionExpired()
        }
        protectionItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline.timeIntervalSinceNow),
            execute: item
        )
        audit.write("protection_extended", [
            "minutes": bounded,
            "deadline": ISO8601DateFormatter().string(from: deadline),
            "trigger": sessionTrigger.rawValue,
        ])
        presentation?.update(status: presentationStatus())
        updateStatusItem()
    }

    func clearProtection() {
        guard curtainOn else { return }
        protectionItem?.cancel()
        protectionItem = nil
        protectionDeadline = nil
        protectionPrompted = false
        sessionProtectionMinutes = 0
        audit.write("protection_cleared", ["reason": "dashboard_unlimited"])
        presentation?.update(status: presentationStatus())
        updateStatusItem()
    }

    func handleReturnHint() {
        guard state == .active,
              presentation?.isActive == true,
              !didShowReturnHint,
              let startedAt = sessionStartedAt,
              Date().timeIntervalSince(startedAt) >= 60 else {
            return
        }
        didShowReturnHint = true
        presentation.showReturnHint("双击或长按 Esc，再用 Touch ID 解锁")
        audit.write("return_hint_shown", [:])
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        let elapsed = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let recording = recorder.snapshot().isRecording
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return DashboardSnapshot(
            curtainState: state,
            recording: recording,
            hotkey: hotkeyDisplay,
            elapsed: elapsedText(elapsed),
            scene: sessionScene,
            sceneMinutes: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map {
                    ($0, config.protectionMinutes(for: $0))
                }
            ),
            scenePresentationLabels: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map {
                    ($0, scenePresentationLabel($0))
                }
            ),
            sceneHotkeys: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map {
                    ($0, config.sceneHotkey(for: $0).displayString)
                }
            ),
            protectionRemaining: protectionDeadline.map { _ in
                elapsedText(TimeInterval(protectionRemainingSeconds()))
            },
            presentationLabel: dashboardPresentationLabel(),
            hasAccessibility: Permissions.hasAccessibility(),
            hasScreenRecording: Permissions.hasScreenRecording(),
            version: version
        )
    }

    func dashboardPresentationLabel() -> String {
        guard config.presentationModeEnabled else { return "黑幕" }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else { return "黑幕" }
        let presentationCount = screens.filter {
            config.displayRole(isMain: $0.isMain) == .presentation
        }.count
        if presentationCount == 0 { return "黑幕" }
        if presentationCount == screens.count { return "时钟" }
        return "混合"
    }

    func scenePresentationLabel(_ scene: CurtainScene) -> String {
        guard config.presentationModeEnabled else { return "黑幕" }
        let profile = config.sceneProfile(for: scene)
        guard profile.usesPresentation else { return "黑幕" }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else { return "黑幕" }
        let count = screens.filter {
            config.displayRole(for: scene, isMain: $0.isMain) == .presentation
        }.count
        if count == 0 { return "黑幕" }
        if count == screens.count { return profile.message.isEmpty ? "展示" : profile.message }
        return "混合"
    }

    func handleHotkey() {
        if state == .active {
            requestExit()
            return
        }
        guard state == .idle else { return }
        startCurtain()
    }

    func startCurtain(
        trigger: CurtainTrigger = .manual,
        protectionMinutes: Int? = nil,
        scene: CurtainScene? = nil
    ) {
        let response = turnOn(
            trigger: trigger,
            protectionMinutes: protectionMinutes ?? config.defaultProtectionMinutes,
            scene: scene
        )
        if !response.ok {
            if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
                // 缺权限：直接摆引导面板，并进入下一个待授权面板。
                showPermissionGuide(openSettings: true)
            } else {
                presentError(response.message)
            }
        }
    }

    @objc func menuStopRecording() {
        guard recorder.isRecording else {
            presentError("当前没有在录制", title: "Curtain")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let response = self.recordStop()
            if !response.ok {
                DispatchQueue.main.async { [weak self] in
                    self?.presentError(response.message, title: "Curtain")
                }
            }
        }
    }

    func presentError(_ message: String, title: String = "幕帘没能开启") {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc func menuQuit() {
        teardown()
        NSApp.terminate(nil)
    }
}
