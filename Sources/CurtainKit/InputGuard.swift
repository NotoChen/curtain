import AppKit
import CoreGraphics

/// HID 级事件拦截。
/// 规则：来源 PID 0（真实硬件）一律吞掉；白名单进程的合成事件放行；其余吞掉。
/// 同时负责「长按 Esc」手势，触发 Touch ID。
public final class InputGuard {
    public private(set) var isEnabled = false
    public var holdToAuthSeconds: Double = 2.0
    public var onHoldEscape: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdWorkItem: DispatchWorkItem?
    private var escDown = false

    public init() {}

    @discardableResult
    public func start() -> Bool {
        if tap != nil { return true }

        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        for t in types { mask |= (1 << t.rawValue) }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guarder = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
                return guarder.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func setEnabled(_ on: Bool) {
        isEnabled = on
        if !on {
            escDown = false
            cancelHold()
        }
    }

    public func stop() {
        escDown = false
        cancelHold()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        runLoopSource = nil
        isEnabled = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统超时会禁用 tap，必须自动重挂，否则键盘就"自由"了。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else { return Unmanaged.passUnretained(event) }

        if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 53 { // Esc
                // 关键：按住时系统会持续发 autorepeat 的 keyDown。
                // 以前每个重复事件都 cancel + 重新计时，计时器永远到不了 2 秒。
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if type == .keyDown, !isRepeat, !escDown {
                    escDown = true
                    scheduleHold()
                } else if type == .keyUp {
                    escDown = false
                    cancelHold()
                }
            }
        }

        // 判定只看来源：PID 0 是真实硬件事件，一律吞掉；其余是合成事件（任意
        // agent、终端、自动化工具），一律放行。不维护任何进程名单。
        let pid = Int32(event.getIntegerValueField(.eventSourceUnixProcessID))
        if pid == 0 { return nil }
        return Unmanaged.passUnretained(event)
    }

    private func scheduleHold() {
        cancelHold()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.onHoldEscape?()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdToAuthSeconds, execute: item)
    }

    private func cancelHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }
}
