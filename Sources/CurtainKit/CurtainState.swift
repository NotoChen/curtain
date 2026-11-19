import Foundation

/// 幕帘的显式状态。所有改变屏幕、输入和认证的操作都先经过这里，
/// 避免 `curtainOn`、`authPending` 等多个布尔值组合出中间态。
public enum CurtainState: Equatable {
    case idle
    case active
    case authenticating

    public var isOn: Bool {
        self == .active || self == .authenticating
    }

    public var isAuthenticating: Bool {
        self == .authenticating
    }
}
