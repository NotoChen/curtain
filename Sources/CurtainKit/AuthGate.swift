import Foundation
import LocalAuthentication

/// 唯一出口：Touch ID。策略用 biometrics-only，连密码回退都不给。
public final class AuthGate {
    public init() {}

    /// 生物识别硬件是否可用。不可用时不能把人锁在外面，调用方应允许直接撤幕。
    public func isAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    public func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            completion(false)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
