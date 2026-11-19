import AppKit
import CurtainKit

extension AppDelegate {
    // MARK: - 幕帘

    func turnOn(
        trigger: CurtainTrigger = .manual,
        protectionMinutes: Int? = nil,
        scene: CurtainScene? = nil
    ) -> ControlResponse {
        if presentationPreview.isActive {
            presentationPreview.stop(notify: false)
        }
        if state == .active {
            if let protectionMinutes {
                configureProtection(
                    minutes: protectionMinutes,
                    auditReason: "updated_by_\(trigger.rawValue)"
                )
                return ControlResponse(
                    ok: true,
                    message: protectionMinutes > 0
                        ? "幕帘已开启，保护时长已更新"
                        : "幕帘已开启，已取消自动结束",
                    data: [
                        "trigger": sessionTrigger.rawValue,
                        "protection_minutes": "\(sessionProtectionMinutes)",
                        "protection_remaining": "\(protectionRemainingSeconds())",
                    ]
                )
            }
            return ControlResponse(ok: true, message: "幕帘已经开着")
        }
        guard state == .idle else {
            return .failure("正在等待 Touch ID，不能重复起幕")
        }
        guard controlServerReady else {
            return .failure("本地控制面不可用，无法安全开启幕帘")
        }
        guard Permissions.hasAccessibility(), Permissions.hasScreenRecording() else {
            return .failure("缺少系统权限，幕帘未开启。请先授权设备控制和数据访问、录屏与系统录音。")
        }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else {
            return .failure("没有可用的显示器，幕帘未开启")
        }
        let profile = scene.map { config.sceneProfile(for: $0) }
        let presentationEnabledForSession = config.presentationModeEnabled
            && profile?.usesPresentation != false
        let presentationScreens = screens.filter {
            displayRole(
                isMain: $0.isMain,
                presentationEnabled: presentationEnabledForSession,
                scene: scene
            ) == .presentation
        }
        let blackScreens = screens.filter {
            displayRole(
                isMain: $0.isMain,
                presentationEnabled: presentationEnabledForSession,
                scene: scene
            ) == .black
        }
        guard !presentationScreens.isEmpty || !blackScreens.isEmpty else {
            return .failure("没有显示器分配到幕帘或展示角色")
        }
        let effectiveMinutes = min(
            1440,
            max(
                0,
                protectionMinutes
                    ?? scene.map { config.protectionMinutes(for: $0) }
                    ?? config.defaultProtectionMinutes
            )
        )

        let startedAt = Date()
        sessionStartedAt = startedAt
        sessionAuthPrompts = 0
        sessionAuthFailures = 0
        activeRecordingStartedAt = nil
        activeRecordingClient = nil
        sessionTrigger = trigger
        sessionScene = scene
        sessionSceneProfile = profile
        sessionPresentationEnabled = presentationEnabledForSession
        didShowReturnHint = false
        sessionProtectionMinutes = effectiveMinutes
        protectionPrompted = false
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }

        func rollback(_ message: String) -> ControlResponse {
            presentation?.close()
            shield?.lower()
            inputGuard.setEnabled(false)
            inputGuard.stop()
            stopPresentationTimer()
            sessionStartedAt = nil
            sessionTrigger = .manual
            sessionScene = nil
            sessionSceneProfile = nil
            sessionPresentationEnabled = false
            didShowReturnHint = false
            sessionProtectionMinutes = 0
            protectionDeadline = nil
            protectionPrompted = false
            audit.write("curtain_start_failed", [
                "trigger": trigger.rawValue,
                "reason": message,
            ])
            return .failure(message)
        }

        NSLog(
            "curtain.turnOn begin displays=%d presentation=%d black=%d",
            screens.count,
            presentationScreens.count,
            blackScreens.count
        )
        guard inputGuard.start() else {
            NSLog("curtain.turnOn tap FAILED")
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionGuide(openSettings: true)
            }
            return .failure("事件拦截启动失败：请在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Curtain，然后重新开启幕帘")
        }

        var presentationStarted = false
        var shieldStarted = false
        if !presentationScreens.isEmpty {
            let sceneImagePath = profile?.backgroundImagePath ?? ""
            let effectiveImagePath = sceneImagePath.isEmpty
                ? config.presentationImagePath
                : sceneImagePath
            let sceneClockStyle = profile?.clockStyle ?? ""
            let effectiveClockStyle = sceneClockStyle.isEmpty
                ? config.presentationClockStyle
                : sceneClockStyle
            if !effectiveImagePath.isEmpty,
               !PresentationBackgroundLoader.isLoadable(
                    path: effectiveImagePath
               ) {
                return rollback("展示模式背景图无法读取：\(effectiveImagePath)")
            }
            presentation.hidesCursor = config.hideCursorDuringCurtain
            presentation.blocksPointerEvents = true
            guard presentation.show(
                screens: presentationScreens,
                color: CurtainColor(hex: config.curtainColor) ?? .black,
                imagePath: effectiveImagePath.isEmpty ? nil : effectiveImagePath,
                clockStyle: PresentationClockStyle.storedValue(
                    effectiveClockStyle
                ),
                imageFocus: CGPoint(
                    x: config.presentationFocusX,
                    y: config.presentationFocusY
                ),
                imageZoom: config.presentationZoom,
                imageDim: config.presentationDim,
                status: presentationStatus()
            ) else {
                return rollback("展示模式窗口创建失败，幕帘未开启")
            }
            presentationStarted = true
            audit.write("presentation_mode", [
                "screens": presentationScreens.count,
                "display_ids": presentationScreens.map { "\($0.displayID)" }.joined(separator: ","),
                "image": effectiveImagePath.isEmpty ? "none" : effectiveImagePath,
                "scene": scene?.rawValue ?? "",
                "message": profile?.message ?? "",
            ])
            NSLog("curtain.turnOn presentation overlay shown")
        }
        if !blackScreens.isEmpty {
            shield.hidesCursor = config.hideCursorDuringCurtain
            shield.backgroundColor = CurtainColor(hex: config.curtainColor) ?? .black
            guard shield.raise(displayIDs: blackScreens.map(\.displayID)) else {
                let error = shield.lastError ?? "无法建立输出层黑幕，幕帘未开启"
                return rollback(
                    presentationStarted ? "\(error)；展示窗口已回滚" : error
                )
            }
            shieldStarted = true
            NSLog("curtain.turnOn shield raised")
        }

        inputGuard.setEnabled(true)
        sentinel.preventsClamshellSleep = config.clamshellModeEnabled
        sentinel.enable()
        state = .active
        healthWatchdog?.start()
        if presentationStarted {
            startPresentationTimer()
        } else {
            stopPresentationTimer()
        }
        configureProtection(
            minutes: effectiveMinutes,
            auditReason: "session_start_\(trigger.rawValue)"
        )
        updateStatusItem()
        audit.write("curtain_on", [
            "displays": screens.count,
            "presentation_displays": presentationStarted ? presentationScreens.count : 0,
            "black_displays": shieldStarted ? blackScreens.count : 0,
            "trigger": trigger.rawValue,
            "scene": scene?.rawValue ?? "",
            "protection_minutes": effectiveMinutes,
            "scene_message": profile?.message ?? "",
        ])
        NSLog("curtain.turnOn complete")

        if config.safetyTimeoutSeconds > 0 {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.curtainOn else { return }
                self.audit.write("curtain_auto_off", ["reason": "safety_timeout"])
                self.turnOff(reason: "safety_timeout")
            }
            safetyItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + config.safetyTimeoutSeconds, execute: item)
        }

        return ControlResponse(ok: true, message: "幕帘已开启", data: [
            "displays": "\(screens.count)",
            "presentation_displays": "\(presentationStarted ? presentationScreens.count : 0)",
            "black_displays": "\(shieldStarted ? blackScreens.count : 0)",
            "trigger": trigger.rawValue,
            "scene": scene?.rawValue ?? "",
            "protection_minutes": "\(effectiveMinutes)",
            "protection_remaining": "\(protectionRemainingSeconds())",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
        ])
    }

    func turnOff(reason: String) {
        guard state.isOn else { return }
        let endedAt = Date()
        let duration = sessionStartedAt.map { endedAt.timeIntervalSince($0) } ?? 0
        state = .idle
        authGeneration &+= 1
        auth.cancel()
        healthWatchdog?.stop()
        safetyItem?.cancel()
        safetyItem = nil
        protectionItem?.cancel()
        protectionItem = nil
        protectionDeadline = nil
        stopPresentationTimer()
        // 先恢复屏幕，再放行物理输入。反过来会留下几毫秒“看不见但能点”的窗口。
        presentation?.close()
        shield.lower()
        inputGuard.setEnabled(false)
        inputGuard.stop()
        sentinel.disable()
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }
        screensAsleepWithClamshell = false
        updateStatusItem()
        audit.write("curtain_off", [
            "reason": reason,
            "trigger": sessionTrigger.rawValue,
        ])
        finishSession(
            reason: reason,
            endedAt: endedAt,
            duration: duration
        )
        sessionTrigger = .manual
        sessionScene = nil
        sessionSceneProfile = nil
        sessionPresentationEnabled = false
        didShowReturnHint = false
        sessionProtectionMinutes = 0
        protectionPrompted = false
    }

    func finishSession(reason: String,
                       endedAt: Date,
                       duration: TimeInterval) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var details: [String: Any] = [
            "reason": reason,
            "duration_seconds": (duration * 10).rounded() / 10,
            "auth_prompts": sessionAuthPrompts,
            "auth_failures": sessionAuthFailures,
            "trigger": sessionTrigger.rawValue,
            "protection_minutes": sessionProtectionMinutes,
        ]
        if let started = sessionStartedAt { details["started_at"] = formatter.string(from: started) }
        details["ended_at"] = formatter.string(from: endedAt)
        if let sessionScene {
            details["scene"] = sessionScene.rawValue
        }
        audit.write("session_summary", details)
        audit.flush()
    }

    /// 双击/长按 Esc、再次按起幕快捷键或 curtainctl off：
    /// 降层级让指纹面板显形，然后只认 Touch ID。
    func requestExit() {
        guard state == .active else { return }

        // 硬件不可用时不能把人锁在黑屏里。
        guard auth.isAvailable() else {
            audit.write("biometrics_unavailable", [:])
            turnOff(reason: "biometrics_unavailable")
            return
        }

        state = .authenticating
        authGeneration &+= 1
        let generation = authGeneration
        updateStatusItem()
        if presentation?.isActive == true {
            presentation.hideForAuth()
        }
        if shield.isUp {
            guard shield.demoteForAuth() else { return }
        }
        inputGuard.setAuthenticationMode(true)
        NSApp.activate(ignoringOtherApps: true)
        sessionAuthPrompts += 1
        audit.write("auth_prompt", [:])

        auth.authenticate(reason: "解除幕帘") { [weak self] ok in
            guard let self else { return }
            guard self.authGeneration == generation, self.state == .authenticating else { return }
            if ok {
                self.turnOff(reason: "touchid")
            } else {
                self.state = .active
                self.inputGuard.setAuthenticationMode(false)
                if self.presentation?.isActive == true {
                    self.presentation.restoreAfterAuth()
                }
                if self.shield.isUp {
                    self.shield.restoreLevel()
                }
                // restoreLevel 失败时会同步触发 fail-closed 撤幕；
                // 不能再把已经被撤下的状态覆盖回 active。
                guard self.state == .active else { return }
                self.sessionAuthFailures += 1
                self.audit.write("auth_failed", [:])
                self.updateStatusItem()
            }
        }
    }

    /// Touch ID 面板显示期间再按一次物理 Esc：取消认证，回到仍然锁住的幕帘。
    func cancelAuthentication() {
        guard state == .authenticating else { return }
        authGeneration &+= 1
        auth.cancel()
        state = .active
        inputGuard.setAuthenticationMode(false)
        if presentation?.isActive == true {
            presentation.restoreAfterAuth()
        }
        if shield.isUp {
            shield.restoreLevel()
        }
        // restoreLevel 失败会同步触发 fail-closed 撤幕，不能把状态覆盖回 active。
        guard state == .active else { return }
        audit.write("auth_cancelled", [:])
        updateStatusItem()
    }

    func configureProtection(minutes: Int, auditReason: String) {
        protectionItem?.cancel()
        protectionItem = nil
        protectionDeadline = nil
        protectionPrompted = false
        sessionProtectionMinutes = min(1440, max(0, minutes))
        guard sessionProtectionMinutes > 0, curtainOn else {
            audit.write("protection_cleared", ["reason": auditReason])
            return
        }
        let seconds = TimeInterval(sessionProtectionMinutes * 60)
        let deadline = Date().addingTimeInterval(seconds)
        protectionDeadline = deadline
        audit.write("protection_scheduled", [
            "minutes": sessionProtectionMinutes,
            "deadline": ISO8601DateFormatter().string(from: deadline),
            "reason": auditReason,
        ])
        let item = DispatchWorkItem { [weak self] in
            self?.protectionExpired()
        }
        protectionItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func protectionExpired() {
        guard curtainOn, state == .active, !protectionPrompted else { return }
        protectionPrompted = true
        audit.write("protection_elapsed", [
            "minutes": sessionProtectionMinutes,
            "trigger": sessionTrigger.rawValue,
        ])
        presentation?.update(status: presentationStatus())
        requestExit()
    }

    func protectionRemainingSeconds() -> Int {
        guard let protectionDeadline else { return 0 }
        return max(0, Int(protectionDeadline.timeIntervalSinceNow.rounded(.up)))
    }

    func presentationStatus() -> PresentationStatus {
        var status = PresentationClockFormatter.status(
            at: Date(),
            startedAt: sessionStartedAt,
            messageText: sessionSceneProfile?.message ?? ""
        )
        if let profile = sessionSceneProfile,
           profile.showsReturnTime,
           let protectionDeadline {
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: protectionDeadline
            )
            status.returnText = String(
                format: "预计 %02d:%02d 回来",
                components.hour ?? 0,
                components.minute ?? 0
            )
        }
        let elapsed = status.elapsedText
        if let protectionDeadline {
            let remaining = Int(protectionDeadline.timeIntervalSinceNow.rounded(.up))
            if remaining > 0 {
                status.elapsedText = "\(elapsed) · 剩余 \(elapsedText(TimeInterval(remaining)))"
            } else {
                status.elapsedText = protectionPrompted
                    ? "已到保护时长 · 等待 Touch ID"
                    : "已到保护时长"
            }
        }
        return status
    }

    func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    func startPresentationTimer() {
        stopPresentationTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.curtainOn else { return }
            self.presentation?.update(status: self.presentationStatus())
        }
        RunLoop.main.add(timer, forMode: .common)
        presentationTimer = timer
    }

    func stopPresentationTimer() {
        presentationTimer?.invalidate()
        presentationTimer = nil
    }
}
