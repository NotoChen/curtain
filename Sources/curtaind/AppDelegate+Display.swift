import AppKit
import CurtainKit

extension AppDelegate {
    /// 场景可以在不修改用户配置的前提下，让本次会话强制使用输出层黑幕。
    func displayRole(isMain: Bool,
                     presentationEnabled: Bool,
                     scene: CurtainScene? = nil) -> CurtainDisplayRole {
        guard presentationEnabled else { return .black }
        return config.displayRole(for: scene, isMain: isMain)
    }

    func effectiveDisplayRole(isMain: Bool) -> CurtainDisplayRole {
        let enabled = curtainOn
            ? sessionPresentationEnabled
            : config.presentationModeEnabled
        return displayRole(
            isMain: isMain,
            presentationEnabled: enabled,
            scene: sessionScene
        )
    }

    @objc func screensChanged() {
        guard curtainOn else { return }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else {
            handlePresentationFailure("所有显示器已断开")
            return
        }
        let presentationScreens = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .presentation
        }
        let blackScreens = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .black
        }
        guard !presentationScreens.isEmpty || !blackScreens.isEmpty else {
            handlePresentationFailure("没有显示器分配到保护角色")
            return
        }
        let blackTargets = Set(blackScreens.map(\.displayID))

        // 先把即将变成黑色的屏幕纳入 gamma，再移除对应展示窗口。
        // 反过来会先关闭窗口、后涂黑，热插拔时露出一帧桌面。
        if !blackTargets.isEmpty {
            let needed = blackTargets.subtracting(shield.displayIDs)
            if !needed.isEmpty || !shield.isUp {
                let union = shield.isUp
                    ? Array(shield.displayIDs.union(needed))
                    : Array(blackTargets)
                let ok = shield.isUp
                    ? shield.reconfigure(displayIDs: union)
                    : shield.raise(displayIDs: union)
                guard ok else {
                    if state.isOn {
                        handleShieldFailure(
                            shield.lastError ?? "显示器变化后无法建立输出层黑幕"
                        )
                    }
                    return
                }
            }
        }

        if presentationScreens.isEmpty {
            presentation.close()
        } else {
            let reconciled = presentation.reconcile(screens: presentationScreens)
            guard reconciled else {
                handlePresentationFailure("显示器变化后无法重建展示模式窗口")
                return
            }
        }

        if blackTargets.isEmpty {
            shield.lower()
        } else if shield.displayIDs != blackTargets {
            guard shield.reconfigure(displayIDs: Array(blackTargets)) else {
                if state.isOn {
                    handleShieldFailure(shield.lastError ?? "显示器变化后无法恢复输出层黑幕")
                }
                return
            }
        }

        if state == .authenticating {
            if presentation.isActive {
                presentation.hideForAuth()
            }
            if shield.isUp {
                _ = shield.demoteForAuth()
            }
        }
        presentation.update(status: presentationStatus())
    }

    func handlePresentationFailure(_ reason: String) {
        guard state.isOn else { return }
        audit.write("presentation_failure", ["reason": reason])
        turnOff(reason: "presentation_failure")
        presentError(
            "\(reason)。为避免状态仍显示为开启但实际没有遮挡，幕帘已自动撤下。",
            title: "幕帘已自动撤下"
        )
    }
}
