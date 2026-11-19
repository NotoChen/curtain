import Foundation
import LocalAuthentication

/// 唯一出口：Touch ID。策略用 biometrics-only，连密码回退都不给。
public final class AuthGate {
    private var activeContext: LAContext?

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
        activeContext = ctx
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] ok, _ in
            DispatchQueue.main.async {
                if self?.activeContext === ctx {
                    self?.activeContext = nil
                }
                completion(ok)
            }
        }
    }

    /// 取消尚未完成的认证；其 completion 仍可能回调，调用方需用 generation 丢弃旧结果。
    public func cancel() {
        activeContext?.invalidate()
        activeContext = nil
    }
}
