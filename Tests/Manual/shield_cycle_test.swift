import AppKit
import CurtainKit
import Foundation

// 回归测试：反复 raise/lower。
// 旧代码 close() 会额外 release 一次（isReleasedWhenClosed 默认 true），
// 与 ARC 强引用叠加造成 over-release，池弹出时崩溃。
// 期间屏幕会短暂变黑（每次约 0.2 秒）。

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let shield = Shield()
let cycles = 4
for i in 0..<cycles {
    shield.raise()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    shield.lower()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    print("cycle \(i + 1)/\(cycles) ok")
    fflush(stdout)
}

// 触发一次主线程 autorelease pool 弹出，over-release 会在这里炸。
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
print("PASS")
