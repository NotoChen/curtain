import AppKit
import ApplicationServices
import CurtainKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 运行状态

    var shield: Shield!
    var presentation: PresentationOverlay!
    let presentationPreview = PresentationPreviewSession()
    var inputGuard: InputGuard!
    var auth: AuthGate!
    var broker: CaptureBroker!
    var recorder: Recorder!
    var sentinel: Sentinel!
    var audit: AuditLog!
    var server: ControlServer!
    var statusItem: NSStatusItem?
    var statusPopover: StatusPopoverController?
    var signalSource: DispatchSourceSignal?
    var intSignalSource: DispatchSourceSignal?

    var config = CurtainConfig.load()
    var state: CurtainState = .idle
    var authGeneration: UInt64 = 0
    var safetyItem: DispatchWorkItem?
    var protectionItem: DispatchWorkItem?
    var protectionDeadline: Date?
    var sessionProtectionMinutes = 0
    var protectionPrompted = false
    var sessionTrigger: CurtainTrigger = .manual
    var sessionScene: CurtainScene?
    var sessionSceneProfile: CurtainSceneProfile?
    var sessionPresentationEnabled = false
    var didShowReturnHint = false
    var automationTimer: Timer?
    var idleTriggerArmed = true
    var scheduleWasInside = false
    var automationRetryAfter = Date.distantPast
    var screensAsleepWithClamshell = false
    var healthWatchdog: HealthWatchdog?
    var globalHotkey: GlobalHotkey?
    var sceneHotkeys: [CurtainScene: GlobalHotkey] = [:]
    var permissionGuide: PermissionGuideController?
    var settingsWindow: SettingsWindowController?
    var onboardingWindow: OnboardingWindowController?
    var presentationTimer: Timer?
    var singleInstance: SingleInstance?
    var controlServerReady = false
    var didTeardown = false
    var sessionStartedAt: Date?
    var sessionAuthPrompts = 0
    var sessionAuthFailures = 0
    var activeRecordingStartedAt: Date?
    var activeRecordingClient: String?

    var curtainOn: Bool { state.isOn }
    var authPending: Bool { state.isAuthenticating }

    // MARK: - 启动与退出

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureSupportDir()

        // 单实例：第二个实例直接退出，避免两个进程抢同一个 socket 和同一块屏。
        let instance = SingleInstance()
        guard instance.acquire() else {
            // 锁被占用时先问一下在跑的那个：能应答就是健康实例，安静退出（
            // launchd 的 RunAtLoad 也会走到这里，不该弹窗打扰用户）。
            if (try? ControlClient.send(ControlRequest(cmd: "status"))) != nil {
                NSApp.terminate(nil)
                return
            }
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "Curtain 已经在运行"
            alert.informativeText = "菜单栏里已经有它的图标，但当前实例没有响应。可以先退出旧实例再打开。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        singleInstance = instance
        if !FileManager.default.fileExists(atPath: Paths.configURL.path) {
            _ = config.save()
        } else {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Paths.configURL.path
            )
        }

        shield = Shield()
        presentation = PresentationOverlay()
        shield.hidesCursor = config.hideCursorDuringCurtain
        presentation.hidesCursor = config.hideCursorDuringCurtain
        shield.backgroundColor = CurtainColor(hex: config.curtainColor) ?? .black
        shield.onUnavailable = { [weak self] message in
            self?.handleShieldFailure(message)
        }
        inputGuard = InputGuard()
        inputGuard.holdToAuthSeconds = config.holdToAuthSeconds
        inputGuard.doubleEscapeSeconds = config.doubleEscapeSeconds
        applyHotkeySettings(to: inputGuard)
        inputGuard.onHoldEscape = { [weak self] in self?.requestExit() }
        inputGuard.onExitHotkey = { [weak self] in self?.requestExit() }
        inputGuard.onCancelAuthentication = { [weak self] in self?.cancelAuthentication() }
        inputGuard.onTapUnavailable = { [weak self] in
            self?.handleHealthFailure("输入拦截 tap 已失效")
        }
        inputGuard.onPhysicalInteraction = { [weak self] in
            self?.handleReturnHint()
        }
        auth = AuthGate()
        broker = CaptureBroker()
        recorder = Recorder()
        recorder.onUnexpectedStop = { [weak self] message in
            guard let self else { return }
            self.audit.write("record_stream_stopped", ["error": message])
            self.activeRecordingStartedAt = nil
            self.activeRecordingClient = nil
            self.updateStatusItem()
        }
        sentinel = Sentinel()
        sentinel.preventsClamshellSleep = config.clamshellModeEnabled
        audit = AuditLog()

        setupStatusItem()
        setupSignalHandling()
        setupHealthWatchdog()
        globalHotkey = GlobalHotkey(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        globalHotkey?.onPressed = { [weak self] in self?.handleHotkey() }
        globalHotkey?.onUnavailable = { [weak self] in
            guard let self else { return }
            self.audit.write("hotkey_unavailable", [:])
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .idle, self.globalHotkey?.isActive != true else { return }
                self.startGlobalHotkeyIfPermitted()
            }
        }
        configureSceneHotkeys()
        startGlobalHotkeyIfPermitted()

        server = ControlServer()
        do {
            try server.start { [weak self] request, peer in
                guard let self else { return ControlResponse.failure("curtaind 已退出") }
                return self.handle(request, peer: peer)
            }
            controlServerReady = true
        } catch {
            NSLog("Curtain control server failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.presentError(
                    "本地控制面启动失败，无法保证 curtainctl 的应急出口可用。\n\n\(error)",
                    title: "Curtain 启动失败"
                )
                NSApp.terminate(nil)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        setupSystemObservers()
        startAutomationScheduler()

        audit.write("daemon_start", ["displays": NSScreen.screens.count])
        preflightAccessibility()

        // 缺权限就直接把引导面板摆出来，而不是等用户点「开启幕帘」才发现。
        if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPermissionGuide()
            }
        } else if !config.hasShownOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    /// 权限入口只打开系统设置和拖拽浮窗，不再叠一个重复的大授权窗口。
    func showPermissionGuide(openSettings: Bool = false) {
        if permissionGuide == nil {
            let controller = PermissionGuideController()
            controller.onAllGranted = { [weak self] in
                guard let self else { return }
                self.audit.write("permissions_granted", [:])
                self.startGlobalHotkeyIfPermitted()
                if !self.config.hasShownOnboarding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.showOnboarding()
                    }
                }
            }
            permissionGuide = controller
        }
        permissionGuide?.present(openSettings: openSettings)
    }

    /// 启动时只做状态检查，不弹系统框：真正申请放到用户点「打开设置」时，
    /// 那时系统会把 Curtain.app 加进对应列表，少一次莫名其妙的弹窗。
    private func preflightAccessibility() {
        let trusted = Permissions.hasAccessibility()
        let screen = Permissions.hasScreenRecording()
        audit.write("accessibility_check", ["trusted": trusted, "screen": screen])
        if !trusted {
            NSLog("Curtain: 设备控制和数据访问 未授权")
        }
        if !screen {
            NSLog("Curtain: 录屏与系统录音 未授权")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = CurtainURLCommand(url: url) else {
                audit.write("url_ignored", ["url": url.absoluteString])
                continue
            }
            switch command.action {
            case .on, .protect:
                startCurtain(
                    trigger: .url,
                    protectionMinutes: command.minutes
                )
            case .off:
                if state == .active {
                    requestExit()
                }
            case .status:
                statusItemClicked()
            case .settings:
                showSettings()
            }
        }
    }

    func teardown() {
        guard !didTeardown else { return }
        didTeardown = true
        healthWatchdog?.stop()
        safetyItem?.cancel()
        safetyItem = nil
        protectionItem?.cancel()
        protectionItem = nil
        automationTimer?.invalidate()
        automationTimer = nil
        auth?.cancel()
        stopPresentationTimer()
        presentationPreview.stop(notify: false)
        presentation?.close()
        permissionGuide?.stop()
        if state.isOn {
            turnOff(reason: "daemon_exit")
        }
        // 状态机之外再兜底清理一次，避免任何异常路径留下 gamma 黑幕或事件 tap。
        shield?.lower()
        inputGuard?.stop()
        sentinel?.disable()
        globalHotkey?.stop()
        globalHotkey = nil
        sceneHotkeys.values.forEach { $0.stop() }
        sceneHotkeys.removeAll()
        server?.stop()
        singleInstance?.release()
        singleInstance = nil
        if let audit {
            audit.write("daemon_stop", [:])
            audit.flush()
        }
    }
}
