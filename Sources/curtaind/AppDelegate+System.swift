import AppKit
import CurtainKit

extension AppDelegate {
    // MARK: - 系统事件

    func setupSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc func systemWillSleep() {
        guard curtainOn else { return }
        audit.write("system_sleep", [:])
        turnOff(reason: "system_sleep")
    }

    @objc func systemDidWake() {
        screensAsleepWithClamshell = false
        if curtainOn {
            screensChanged()
        }
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }
    }

    /// 未授权时不要创建事件 tap：CGEventTap 会触发 macOS 自己的 TCC 同意框。
    /// 用户从授权浮窗完成授权后，onAllGranted 会再次调用这里。
    func startGlobalHotkeyIfPermitted() {
        guard Permissions.hasAccessibility() else { return }
        if globalHotkey?.start() == false {
            NSLog("Curtain: global hotkey monitor could not be started")
        }
        for (scene, hotkey) in sceneHotkeys where hotkey.start() == false {
            NSLog(
                "Curtain: scene hotkey monitor could not be started: \(scene.rawValue)"
            )
        }
    }

    @objc func sessionResigned() {
        guard curtainOn else { return }
        audit.write("session_resigned", [:])
        turnOff(reason: "session_inactive")
    }

    @objc func screensDidSleep() {
        guard curtainOn else { return }
        audit.write("screens_sleep", [:])
        if config.clamshellModeEnabled {
            screensAsleepWithClamshell = true
            audit.write("screens_sleep_kept_for_clamshell", [:])
            return
        }
        turnOff(reason: "screens_sleep")
    }

    @objc func screensDidWake() {
        if curtainOn {
            screensChanged()
        }
        screensAsleepWithClamshell = false
    }

    // MARK: - 生命周期保障

    func setupSignalHandling() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.teardown()
            exit(1)
        }
        source.resume()
        signalSource = source

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.teardown()
            exit(1)
        }
        intSource.resume()
        intSignalSource = intSource
    }

    func setupHealthWatchdog() {
        let watchdog = HealthWatchdog()
        watchdog.check = { [weak self] in
            guard let self else { return "curtaind 已退出" }
            if !Permissions.hasAccessibility() {
                return "「设备控制和数据访问」权限已撤销"
            }
            if !Permissions.hasScreenRecording() {
                return "「录屏与系统录音」权限已撤销"
            }
            if !self.inputGuard.healthCheck() {
                return "输入拦截 tap 已失效且无法恢复"
            }
            return nil
        }
        watchdog.onFailure = { [weak self] reason in
            self?.handleHealthFailure(reason)
        }
        watchdog.onMainThreadStalled = {
            NSLog("Curtain: main thread stalled; terminating to restore input and screen")
            exit(70)
        }
        healthWatchdog = watchdog
    }

    func handleHealthFailure(_ reason: String) {
        guard state.isOn else { return }
        audit.write("health_failure", ["reason": reason])
        turnOff(reason: "health_failure")
        presentError(
            "\(reason)。为避免在看不见的情况下误操作，幕帘已自动撤下。请重新授权后再开启。",
            title: "幕帘已自动撤下"
        )
    }

    func handleShieldFailure(_ reason: String) {
        guard state.isOn else { return }
        audit.write("shield_failure", ["reason": reason])
        turnOff(reason: "shield_failure")
        presentError(
            "\(reason)。为避免黑屏但实际可被物理操作，幕帘已自动撤下。",
            title: "幕帘已自动撤下"
        )
    }

    func curtainStateString() -> String {
        onMain { self.curtainOn ? "on" : "off" }
    }

    func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
