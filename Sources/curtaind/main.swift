import AppKit
import ApplicationServices
import CurtainKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shield: Shield!
    private var inputGuard: InputGuard!
    private var auth: AuthGate!
    private var broker: CaptureBroker!
    private var recorder: Recorder!
    private var sentinel: Sentinel!
    private var audit: AuditLog!
    private var server: ControlServer!
    private var statusItem: NSStatusItem?
    private var signalSource: DispatchSourceSignal?

    private var config = CurtainConfig.load()
    private var curtainOn = false
    private var authPending = false
    private var safetyItem: DispatchWorkItem?
    private var permissionWindow: PermissionWindowController?
    private var settingsWindow: SettingsWindowController?
    private var singleInstance: SingleInstance?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureSupportDir()
        config.save()

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

        shield = Shield()
        shield.hidesCursor = config.hideCursorDuringCurtain
        inputGuard = InputGuard()
        inputGuard.allowlist = config.allowlist
        inputGuard.holdToAuthSeconds = config.holdToAuthSeconds
        inputGuard.onHoldEscape = { [weak self] in self?.requestExit() }
        auth = AuthGate()
        broker = CaptureBroker()
        recorder = Recorder()
        sentinel = Sentinel()
        audit = AuditLog()

        setupStatusItem()
        setupSignalHandling()

        server = ControlServer()
        do {
            try server.start { [weak self] request in
                guard let self else { return ControlResponse.failure("curtaind 已退出") }
                return self.handle(request)
            }
        } catch {
            NSLog("Curtain control server failed: \(error)")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        audit.write("daemon_start", ["displays": NSScreen.screens.count])
        preflightAccessibility()

        // 缺权限就直接把引导面板摆出来，而不是等用户点「开启幕帘」才发现。
        if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPermissionGuide()
            }
        }
    }

    /// 引导面板：每项权限一行，点「打开设置」直达系统面板，授权后状态灯自动变绿。
    private func showPermissionGuide(openAccessibility: Bool = false) {
        if permissionWindow == nil {
            let controller = PermissionWindowController()
            controller.onAllGranted = { [weak self] in
                self?.audit.write("permissions_granted", [:])
            }
            permissionWindow = controller
        }
        permissionWindow?.show()
        if openAccessibility {
            Permissions.openAccessibilitySettings()
        }
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

    // MARK: - 控制协议

    private func handle(_ request: ControlRequest) -> ControlResponse {
        switch request.cmd {
        case "on":
            return onMain { self.turnOn() }
        case "off":
            return onMain {
                self.requestExit()
                return ControlResponse(ok: true, message: "已请求 Touch ID，验证通过后撤幕")
            }
        case "panic":
            // 应急出口：只走本地 shell，猫不可能敲命令。用于指纹路径失效时自救。
            return onMain {
                guard self.curtainOn else { return ControlResponse(ok: true, message: "幕帘本来就没开") }
                self.audit.write("panic_off", [:])
                self.turnOff(reason: "panic")
                return ControlResponse(ok: true, message: "已强制撤幕（panic）")
            }
        case "status":
            return onMain { self.status() }
        case "doctor":
            return onMain { self.doctorReport() }
        case "capture":
            return capture(request)
        case "record_start":
            return recordStart(request)
        case "record_stop":
            return recordStop()
        case "audit":
            let lines = audit.tail(request.display ?? 20)
            return ControlResponse(ok: true, message: lines.joined(separator: "\n"), data: ["count": "\(lines.count)"])
        default:
            return .failure("未知命令：\(request.cmd)")
        }
    }

    private func status() -> ControlResponse {
        let data: [String: String] = [
            "curtain": curtainOn ? "on" : "off",
            "displays": "\(NSScreen.screens.count)",
            "auth_pending": authPending ? "yes" : "no",
            "recording": recorder.isRecording ? "yes" : "no",
            "allowlist": "\(config.allowlist.count)",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
            "accessibility": Permissions.hasAccessibility() ? "granted" : "missing",
            "screen_recording": Permissions.hasScreenRecording() ? "granted" : "missing",
        ]
        return ControlResponse(ok: true, message: curtainOn ? "幕帘已开启" : "幕帘已关闭", data: data)
    }

    private func capture(_ request: ControlRequest) -> ControlResponse {
        let options = captureOptions(request)
        do {
            if request.allDisplays == true {
                let fallback = defaultOutputURL(extension: "png").deletingLastPathComponent()
                let dir = request.out.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? fallback
                let base = request.out.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                    ?? "shot-\(Int(Date().timeIntervalSince1970))"
                let results = try broker.screenshotAllDisplays(to: dir, baseName: base, options: options)
                audit.write("capture_all", ["count": results.count, "dir": dir.path, "cursor": options.cursor])
                return ControlResponse(ok: true, message: "已保存 \(results.count) 张（每屏一张）", data: [
                    "count": "\(results.count)",
                    "dir": dir.path,
                    "paths": results.map { $0.url.path }.joined(separator: ","),
                ])
            }

            let out = request.out ?? defaultOutputURL(extension: "png").path
            let result = try broker.screenshot(to: URL(fileURLWithPath: out),
                                               displayIndex: request.display ?? 0,
                                               options: options)
            audit.write("capture", [
                "path": result.url.path,
                "width": result.width,
                "height": result.height,
                "sha256": result.sha256,
                "cursor": options.cursor,
                "region": request.region ?? "",
                "curtain": curtainOn ? "on" : "off",
            ])
            return ControlResponse(ok: true, message: "已保存", data: [
                "path": result.url.path,
                "width": "\(result.width)",
                "height": "\(result.height)",
                "sha256": result.sha256,
            ])
        } catch {
            audit.write("capture_failed", ["error": "\(error)"])
            return .failure("截图失败：\(error)")
        }
    }

    private func captureOptions(_ request: ControlRequest) -> CaptureOptions {
        var region: CGRect?
        if let raw = request.region {
            let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                region = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        return CaptureOptions(
            cursor: request.cursor ?? config.captureCursor,
            region: region,
            fps: max(1, min(request.fps ?? config.recordingFPS, 60)),
            bitrate: max(0, request.bitrate ?? config.recordingBitrate)
        )
    }

    /// 默认输出位置：设置里指定的目录，否则 Application Support。
    private func defaultOutputURL(extension ext: String) -> URL {
        let directory = config.captureDirectory.isEmpty
            ? Paths.supportDir
            : URL(fileURLWithPath: config.captureDirectory, isDirectory: true)
        return directory.appendingPathComponent("curtain-\(Int(Date().timeIntervalSince1970)).\(ext)")
    }

    private func recordStart(_ request: ControlRequest) -> ControlResponse {
        guard !recorder.isRecording else { return .failure("已经在录制") }
        let out = request.out ?? defaultOutputURL(extension: "mp4").path
        let options = captureOptions(request)
        do {
            try broker.startRecording(recorder, to: URL(fileURLWithPath: out),
                                      displayIndex: request.display ?? 0, options: options)
            audit.write("record_start", [
                "path": out,
                "fps": options.fps,
                "bitrate": options.bitrate,
                "curtain": curtainOn ? "on" : "off",
            ])
            updateStatusItem()
            return ControlResponse(ok: true, message: "开始录制", data: [
                "path": out,
                "fps": "\(options.fps)",
                "bitrate": "\(options.bitrate)",
            ])
        } catch {
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("录制启动失败：\(error)")
        }
    }

    private func recordStop() -> ControlResponse {
        do {
            let frames = recorder.framesAppended
            let url = try recorder.stop()
            updateStatusItem()
            audit.write("record_stop", ["path": url.path, "frames": frames])
            return ControlResponse(ok: true, message: "录制结束", data: ["path": url.path, "frames": "\(frames)"])
        } catch {
            updateStatusItem()
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("结束录制失败：\(error)")
        }
    }

    // MARK: - 自检

    private func doctorReport() -> ControlResponse {
        var lines: [String] = []
        let ax = Permissions.hasAccessibility()
        let screen = Permissions.hasScreenRecording()
        lines.append("权限 设备控制和数据访问：\(ax ? "已授权" : "缺失")")
        lines.append("权限 录屏与系统录音：\(screen ? "已授权" : "缺失")")

        let displayCount = NSScreen.screens.count
        let sckCount = broker.displayCount()
        lines.append("显示器：\(displayCount) 块（SCK 可见 \(sckCount) 块）")
        lines.append("事件 tap：\(canCreateTap() ? "可创建" : "创建失败")")
        lines.append("Touch ID：\(auth.isAvailable() ? "可用" : "不可用")")

        let agent = LaunchAgent.status()
        lines.append("开机自启：\(agent.installed ? "已安装" : "未安装")\(agent.installed ? (agent.loaded ? "、已加载" : "、未加载") : "")")

        let verify = AuditLog.verify()
        let auditLine = verify.ok
            ? "审计：\(verify.count) 条已校验" + (verify.legacy > 0 ? "（另有 \(verify.legacy) 条旧格式）" : "") + "，哈希链完整"
            : "审计：第 \(verify.brokenAtLine ?? -1) 行断裂（\(verify.reason ?? "")）"
        lines.append(auditLine)

        lines.append("签名：\(signingIdentity())")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        lines.append("版本：\(version)")
        lines.append("可执行文件：\(Bundle.main.bundlePath)")
        lines.append("状态：幕帘\(curtainOn ? "开启" : "关闭")、录屏\(recorder.isRecording ? "进行中" : "空闲")")

        let data: [String: String] = [
            "accessibility": ax ? "granted" : "missing",
            "screen_recording": screen ? "granted" : "missing",
            "displays": "\(displayCount)",
            "tap": canCreateTap() ? "ok" : "failed",
            "touchid": auth.isAvailable() ? "ok" : "unavailable",
            "audit_ok": verify.ok ? "yes" : "no",
            "launch_agent": agent.installed ? "installed" : "absent",
        ]
        return ControlResponse(ok: true, message: lines.joined(separator: "\n"), data: data)
    }

    /// 只创建并立刻销毁一个 listen-only tap，用来判断事件拦截权限是否到位。
    private func canCreateTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    private func signingIdentity() -> String {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: getpid()] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code, let staticCode = try? staticCode(of: code) else {
            return "未知"
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "未知" }
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? "?"
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let certs = dict[kSecCodeInfoCertificates as String] as? [Any]
        let kind = certs == nil ? "ad-hoc" : (team.map { "Team \($0)" } ?? "自签名")
        return "\(identifier)（\(kind)）"
    }

    private func staticCode(of code: SecCode) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecCodeCopyStaticCode(code, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return staticCode
    }

    // MARK: - 幕帘

    private func turnOn() -> ControlResponse {
        guard !curtainOn else { return ControlResponse(ok: true, message: "幕帘已经开着") }
        NSLog("curtain.turnOn begin displays=%d", NSScreen.screens.count)
        shield.raise()
        NSLog("curtain.turnOn shield raised")
        guard inputGuard.start() else {
            NSLog("curtain.turnOn tap FAILED")
            shield.lower()
            NSLog("curtain.turnOn shield lowered after failure")
            DispatchQueue.main.async { [weak self] in self?.showPermissionGuide() }
            return .failure("事件拦截启动失败：请在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Curtain，然后重新开启幕帘")
        }
        NSLog("curtain.turnOn tap ok")
        inputGuard.setEnabled(true)
        sentinel.enable()
        curtainOn = true
        updateStatusItem()
        audit.write("curtain_on", ["displays": NSScreen.screens.count])
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
            "displays": "\(NSScreen.screens.count)",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
        ])
    }

    private func turnOff(reason: String) {
        guard curtainOn else { return }
        safetyItem?.cancel()
        safetyItem = nil
        inputGuard.setEnabled(false)
        inputGuard.stop()
        shield.lower()
        sentinel.disable()
        curtainOn = false
        updateStatusItem()
        audit.write("curtain_off", ["reason": reason])
    }

    /// 长按 Esc 或 curtainctl off：降层级让指纹面板显形，然后只认 Touch ID。
    private func requestExit() {
        guard curtainOn, !authPending else { return }

        // 硬件不可用时不能把人锁在黑屏里。
        guard auth.isAvailable() else {
            audit.write("biometrics_unavailable", [:])
            turnOff(reason: "biometrics_unavailable")
            return
        }

        authPending = true
        shield.demoteForAuth()
        NSApp.activate(ignoringOtherApps: true)
        audit.write("auth_prompt", [:])

        auth.authenticate(reason: "解除幕帘") { [weak self] ok in
            guard let self else { return }
            self.authPending = false
            if ok {
                self.turnOff(reason: "touchid")
            } else {
                self.shield.restoreLevel()
                self.audit.write("auth_failed", [:])
            }
        }
    }

    private func teardown() {
        safetyItem?.cancel()
        safetyItem = nil
        permissionWindow?.stopPolling()
        singleInstance?.release()
        singleInstance = nil
        if curtainOn {
            inputGuard.setEnabled(false)
            inputGuard.stop()
            shield.lower()
            sentinel.disable()
            curtainOn = false
        }
        server?.stop()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "▢"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "开启幕帘", action: #selector(menuOn), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "解除幕帘（长按 Esc → Touch ID）", action: #selector(menuOff), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "结束录制", action: #selector(menuStopRecording), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "权限状态…", action: #selector(menuPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "状态", action: #selector(menuStatus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Curtain", action: #selector(menuQuit), keyEquivalent: "q"))

        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem() {
        let title: String
        if authPending {
            title = "🔒"
        } else if recorder.isRecording {
            title = "⏺"
        } else if curtainOn {
            title = "⬛︎"
        } else {
            title = "▢"
        }
        statusItem?.button?.title = title
    }

    @objc private func menuOn() {
        // 不在菜单追踪过程中建 shielding 窗口：等这一轮 runloop 结束、菜单关掉再动。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let response = self.turnOn()
            if !response.ok {
                if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
                    // 缺权限：直接摆引导面板，并顺手打开缺的那个面板。
                    self.showPermissionGuide(openAccessibility: !Permissions.hasAccessibility())
                } else {
                    self.presentError(response.message)
                }
            }
        }
    }

    @objc private func menuOff() {
        DispatchQueue.main.async { [weak self] in self?.requestExit() }
    }

    @objc private func menuPermissions() {
        DispatchQueue.main.async { [weak self] in self?.showPermissionGuide() }
    }

    @objc private func menuSettings() {
        DispatchQueue.main.async { [weak self] in self?.showSettings() }
    }

    /// 设置窗口：保存后立即生效（不必重启 app）。
    private func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(config: config)
            controller.onSave = { [weak self] updated in
                guard let self else { return }
                self.config = updated
                self.shield.hidesCursor = updated.hideCursorDuringCurtain
                self.inputGuard.allowlist = updated.allowlist
                self.inputGuard.holdToAuthSeconds = updated.holdToAuthSeconds
                self.audit.write("config_saved", [
                    "hold": updated.holdToAuthSeconds,
                    "allowlist": updated.allowlist.count,
                    "fps": updated.recordingFPS,
                ])
            }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    @objc private func menuStopRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.recorder.isRecording else {
                self.presentError("当前没有在录制", title: "Curtain")
                return
            }
            _ = self.recordStop()
        }
    }

    private func presentError(_ message: String, title: String = "幕帘没能开启") {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func menuStatus() {
        let data = status().data ?? [:]
        let axGranted = data["accessibility"] == "granted"
        let screenGranted = data["screen_recording"] == "granted"
        let permissionLine: String
        switch (axGranted, screenGranted) {
        case (true, true): permissionLine = "权限：均已授权"
        case (false, false): permissionLine = "权限：两项都未授权"
        case (false, true): permissionLine = "权限：缺少「设备控制和数据访问」"
        case (true, false): permissionLine = "权限：缺少「录屏与系统录音」"
        }

        let lines = [
            "幕帘：\(data["curtain"] == "on" ? "已开启" : "已关闭")",
            permissionLine,
            "显示器：\(data["displays"] ?? "?") 块",
            "录屏：\(data["recording"] == "yes" ? "正在录制" : "未在录制")",
            "可注入输入的进程：\(data["allowlist"] ?? "?") 个",
            "长按 Esc 解除：\(data["hold_to_auth"] ?? "?")",
        ]

        let alert = NSAlert()
        alert.messageText = "Curtain 运行状态"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "复制诊断信息")
        if alert.runModal() == .alertSecondButtonReturn {
            let raw = data.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(raw, forType: .string)
        }
    }

    @objc private func menuQuit() {
        teardown()
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        shield.rebuildIfNeeded()
    }

    // MARK: - 工具

    private func setupSignalHandling() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.teardown()
            NSApp.terminate(nil)
        }
        source.resume()
        signalSource = source

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.teardown()
            NSApp.terminate(nil)
        }
        intSource.resume()
        intSignalSource = intSource
    }

    private var intSignalSource: DispatchSourceSignal?

    private func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
