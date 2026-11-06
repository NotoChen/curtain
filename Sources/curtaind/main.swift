import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureSupportDir()
        config.save()

        shield = Shield()
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
        case "status":
            return onMain { self.status() }
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
        ]
        return ControlResponse(ok: true, message: curtainOn ? "幕帘已开启" : "幕帘已关闭", data: data)
    }

    private func capture(_ request: ControlRequest) -> ControlResponse {
        let out = request.out ?? Paths.supportDir
            .appendingPathComponent("shot-\(Int(Date().timeIntervalSince1970)).png").path
        do {
            let result = try broker.screenshot(to: URL(fileURLWithPath: out), displayIndex: request.display ?? 0)
            audit.write("capture", [
                "path": result.url.path,
                "width": result.width,
                "height": result.height,
                "sha256": result.sha256,
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

    private func recordStart(_ request: ControlRequest) -> ControlResponse {
        guard !recorder.isRecording else { return .failure("已经在录制") }
        let out = request.out ?? Paths.supportDir
            .appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970)).mp4").path
        do {
            try broker.startRecording(recorder, to: URL(fileURLWithPath: out), displayIndex: request.display ?? 0)
            audit.write("record_start", ["path": out, "curtain": curtainOn ? "on" : "off"])
            return ControlResponse(ok: true, message: "开始录制", data: ["path": out])
        } catch {
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("录制启动失败：\(error)")
        }
    }

    private func recordStop() -> ControlResponse {
        do {
            let frames = recorder.framesAppended
            let url = try recorder.stop()
            audit.write("record_stop", ["path": url.path, "frames": frames])
            return ControlResponse(ok: true, message: "录制结束", data: ["path": url.path, "frames": "\(frames)"])
        } catch {
            audit.write("record_failed", ["error": "\(error)"])
            return .failure("结束录制失败：\(error)")
        }
    }

    // MARK: - 幕帘

    private func turnOn() -> ControlResponse {
        guard !curtainOn else { return ControlResponse(ok: true, message: "幕帘已经开着") }
        shield.raise()
        guard inputGuard.start() else {
            shield.lower()
            return .failure("事件拦截启动失败：请在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Curtain")
        }
        inputGuard.setEnabled(true)
        sentinel.enable()
        curtainOn = true
        updateStatusItem()
        audit.write("curtain_on", ["displays": NSScreen.screens.count])

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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "状态", action: #selector(menuStatus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Curtain", action: #selector(menuQuit), keyEquivalent: "q"))

        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem() {
        statusItem?.button?.title = curtainOn ? "⬛︎" : "▢"
    }

    @objc private func menuOn() {
        _ = turnOn()
    }

    @objc private func menuOff() {
        requestExit()
    }

    @objc private func menuStatus() {
        let s = status()
        let alert = NSAlert()
        alert.messageText = s.message
        alert.informativeText = (s.data ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
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
