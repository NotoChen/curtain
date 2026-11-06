import CurtainKit
import CoreGraphics
import Foundation

// 复现真实场景：按住 Esc 整整 3 秒，期间系统持续发 autorepeat 的 keyDown。
// 判定点：在松开（keyUp）之前是否已经触发退出。
// 旧逻辑每个 repeat 都 cancel + 重新计时，按住期间永远不触发；
// 新逻辑忽略 repeat，按下 0.6 秒后准时触发。

let guarder = InputGuard()
guarder.holdToAuthSeconds = 0.6
guarder.allowlist = []

var fired = 0
guarder.onHoldEscape = {
    fired += 1
    print("HOLD_FIRED count=\(fired)")
    fflush(stdout)
}

guard guarder.start() else {
    print("TAP_CREATE_FAILED")
    exit(1)
}

func pump(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        CFRunLoopRunInMode(.defaultMode, 0.01, false)
    }
}

func post(_ repeatFlag: Int64, _ down: Bool) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)!
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatFlag)
    event.post(tap: .cghidEventTap)
}

guarder.setEnabled(true)

// 按住 3 秒，全程重复
post(0, true)
let holdUntil = Date().addingTimeInterval(3.0)
while Date() < holdUntil {
    pump(0.03)
    post(1, true)
}
let firedDuringHold = fired
print("fired before keyUp = \(firedDuringHold)")
post(0, false)
pump(0.2)

// 再按一次，确认释放后能重新触发
post(0, true)
pump(1.0)
post(0, false)
pump(0.2)

guarder.setEnabled(false)
guarder.stop()

print("total fired = \(fired)")
let ok = firedDuringHold >= 1 && fired >= 2
print(ok ? "PASS" : "FAIL")
exit(ok ? 0 : 1)
