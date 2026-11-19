import AppKit
import CurtainKit

extension AppDelegate {
    // MARK: - 控制协议

    func handle(_ request: ControlRequest, peer: ProcessPeer?) -> ControlResponse {
        switch request.cmd {
        case "on":
            return onMain {
                self.turnOn(
                    trigger: .cli,
                    protectionMinutes: request.minutes
                )
            }
        case "protect":
            return onMain {
                self.turnOn(
                    trigger: .cli,
                    protectionMinutes: request.minutes
                )
            }
        case "scene":
            return onMain {
                guard let raw = request.scene,
                      let scene = CurtainScene(rawValue: raw) else {
                    return .failure(
                        "未知场景；可选 away、meeting、guest、focus"
                    )
                }
                return self.turnOn(
                    trigger: .scene,
                    protectionMinutes: request.minutes
                        ?? self.config.protectionMinutes(for: scene),
                    scene: scene
                )
            }
        case "off":
            return onMain {
                guard self.curtainOn else {
                    return ControlResponse(ok: true, message: "幕帘本来就没开")
                }
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
            return onMain {
                self.status(
                    caller: self.requestCaller(request, peer: peer),
                    peer: peer
                )
            }
        case "doctor":
            return doctorReport()
        case "capture":
            return capture(request, peer: peer)
        case "record_start":
            return recordStart(request, peer: peer)
        case "record_stop":
            return recordStop()
        case "audit":
            let count = request.display ?? 20
            guard count > 0, count <= 10_000 else {
                return .failure("audit 条数必须在 1–10000 之间")
            }
            let lines = audit.tail(count)
            return ControlResponse(ok: true, message: lines.joined(separator: "\n"), data: ["count": "\(lines.count)"])
        default:
            return .failure("未知命令：\(request.cmd)")
        }
    }

    func status(caller: String? = nil, peer: ProcessPeer? = nil) -> ControlResponse {
        let recording = recorder.snapshot()
        let screens = ScreenInventory.current()
        let presentationIDs = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .presentation
        }.map(\.displayID)
        let blackIDs = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .black
        }.map(\.displayID)
        let hotkeyText = HotkeyPolicy.displayString(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        let sceneHotkeyText = CurtainScene.allCases.map {
            "\($0.rawValue)=\(config.sceneHotkey(for: $0).displayString)"
        }.joined(separator: ",")
        let sceneHotkeyActiveCount = sceneHotkeys.values.filter(\.isActive).count
        let data: [String: String] = [
            "curtain": curtainOn ? "on" : "off",
            "displays": "\(NSScreen.screens.count)",
            "display_ids": screens.map { "\($0.displayID)" }.joined(separator: ","),
            "presentation_display_ids": presentationIDs.map(String.init).joined(separator: ","),
            "black_display_ids": blackIDs.map(String.init).joined(separator: ","),
            "auth_pending": authPending ? "yes" : "no",
            "recording": recording.isRecording ? "yes" : "no",
            "recording_frames": "\(recording.framesAppended)",
            "recording_error": recording.lastError ?? "",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
            "double_escape": "\(config.doubleEscapeSeconds)s",
            "curtain_color": config.curtainColor,
            "hotkey": hotkeyText,
            "global_hotkey": globalHotkey?.isActive == true ? "active" : "inactive",
            "scene_hotkeys": sceneHotkeyText,
            "scene_hotkeys_active": "\(sceneHotkeyActiveCount)/\(sceneHotkeys.count)",
            "accessibility": Permissions.hasAccessibility() ? "granted" : "missing",
            "screen_recording": Permissions.hasScreenRecording() ? "granted" : "missing",
            "input_gestures": curtainOn
                ? (inputGuard.gesturesProtected ? "protected" : "unavailable")
                : "idle",
            "caller": caller ?? "unknown",
            "caller_process": peer?.direct.name ?? "",
            "caller_parent": peer?.principal.name ?? "",
            "caller_environment": peer?.environmentHint ?? "",
            "caller_chain": peer?.chainText ?? "",
            "trigger": self.sessionTrigger.rawValue,
            "scene": self.sessionScene?.rawValue ?? "",
            "protection_minutes": "\(self.sessionProtectionMinutes)",
            "protection_remaining": "\(self.protectionRemainingSeconds())",
            "idle_auto_curtain": self.config.idleAutoCurtainEnabled ? "on" : "off",
            "idle_seconds": "\(Int(InputIdleMonitor.secondsSinceLastInput()))",
            "schedule": self.config.scheduleEnabled ? "on" : "off",
            "clamshell": self.config.clamshellModeEnabled ? "on" : "off",
            "screens_asleep": self.screensAsleepWithClamshell ? "yes" : "no",
        ]
        return ControlResponse(ok: true, message: curtainOn ? "幕帘已开启" : "幕帘已关闭", data: data)
    }
}
