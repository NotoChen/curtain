import AppKit
import CoreGraphics

/// HID 级事件拦截。
/// 规则：来源 PID 0（真实硬件）一律吞掉；白名单进程的合成事件放行；其余吞掉。
/// 同时负责「长按 Esc」手势，触发 Touch ID。
public final class InputGuard {
    public private(set) var isEnabled = false
    public var allowlist: [String] = []
    public var holdToAuthSeconds: Double = 2.0
    public var onHoldEscape: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdWorkItem: DispatchWorkItem?
    private let selfPID = getpid()

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
        if !on { cancelHold() }
    }

    public func stop() {
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
                if type == .keyDown { scheduleHold() } else { cancelHold() }
            }
        }

        let pid = Int32(event.getIntegerValueField(.eventSourceUnixProcessID))
        if pid == 0 { return nil }                      // 硬件输入
        if pid == selfPID { return Unmanaged.passUnretained(event) }
        if isAllowed(pid) { return Unmanaged.passUnretained(event) }
        return nil
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

    private func isAllowed(_ pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        let bundle = app.bundleIdentifier ?? ""
        let exe = app.executableURL?.path ?? ""
        for entry in allowlist {
            if entry.hasPrefix("/") {
                if !exe.isEmpty && (exe == entry || exe.hasPrefix(entry)) { return true }
            } else if entry == bundle {
                return true
            }
        }
        return false
    }
}
