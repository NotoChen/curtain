import AppKit
import CoreGraphics
import Foundation

/// 输入事件的纯策略层，便于单测。真正的 tap 只负责把系统事件翻译成这里的结论。
public enum InputDisposition: Equatable {
    case pass
    case block
    case beginHold
    case cancelHold
}

public enum InputPolicy {
    /// CoreGraphics 没有公开的 CGEventType case，但它们会出现在 session 事件流里：
    /// 旋转/缩放手势、Dock 的 Space/Mission Control 控制流、三指滑动等。
    /// 30 与 NSEvent.magnify 共用原始值，必须按 Dock control 处理。
    public static let gestureEventRawValues: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32]

    public static func isGesture(rawValue: UInt32) -> Bool {
        gestureEventRawValues.contains(rawValue)
    }

    /// 物理事件（来源 PID 0）一律拦；合成事件一律放行。
    /// 手势流没有可靠的合成来源，作为物理输入的一部分全部拦掉，避免 Space 切换时
    /// 把幕帘后面的桌面短暂露出来。
    public static func disposition(rawEventType: UInt32,
                                   keyCode: Int64?,
                                   isRepeat: Bool,
                                   sourcePID: Int32,
                                   isEnabled: Bool,
                                   authenticationMode: Bool = false) -> InputDisposition {
        guard isEnabled else { return .pass }
        if isGesture(rawValue: rawEventType) { return .block }
        if authenticationMode {
            // Touch ID 使用独立硬件，认证面板不需要键盘或鼠标输入。
            // 幕帘仍然存在，不能让物理输入穿透到下面的应用。
            return sourcePID == 0 ? .block : .pass
        }
        guard sourcePID == 0 else { return .pass }

        if rawEventType == CGEventType.keyDown.rawValue, keyCode == 53, !isRepeat {
            return .beginHold
        }
        if rawEventType == CGEventType.keyUp.rawValue, keyCode == 53 {
            return .cancelHold
        }
        return .block
    }
}

struct DoubleEscapeRecognizer {
    private var lastDownAt: Date?

    /// 返回 true 表示这是窗口内的第二次按下，应触发退出。
    mutating func registerDown(at now: Date = Date(), window: TimeInterval) -> Bool {
        let boundedWindow = max(0.1, window)
        if let lastDownAt, now.timeIntervalSince(lastDownAt) <= boundedWindow {
            self.lastDownAt = nil
            return true
        }
        lastDownAt = now
        return false
    }

    mutating func reset() {
        lastDownAt = nil
    }
}

/// 系统可能因为回调超时或输入压力反复禁用事件 tap。无限重试会让界面看起来
/// 仍在保护，实际物理输入却可能漏过去；这里用一个短窗口熔断，交给上层撤幕。
struct ReenableCircuitBreaker {
    static let threshold = 5
    static let window: TimeInterval = 10
    static let stableResetInterval: TimeInterval = 30

    private var attempts = 0
    private var windowStart: Date?
    private var lastAttempt: Date?
    private(set) var isTripped = false

    mutating func recordAttempt(at now: Date = Date()) -> Bool {
        if let windowStart, now.timeIntervalSince(windowStart) <= Self.window {
            attempts += 1
        } else {
            self.windowStart = now
            attempts = 1
        }
        lastAttempt = now
        if attempts >= Self.threshold {
            isTripped = true
        }
        return isTripped
    }

    mutating func resetIfStable(at now: Date = Date()) -> Bool {
        guard let lastAttempt,
              now.timeIntervalSince(lastAttempt) >= Self.stableResetInterval else {
            return false
        }
        attempts = 0
        windowStart = nil
        self.lastAttempt = nil
        isTripped = false
        return true
    }
}

/// HID 级事件拦截。
/// 规则：来源 PID 0（真实硬件）一律吞掉；合成事件一律放行；系统手势流单独拦。
/// 同时负责「长按 Esc」手势，触发 Touch ID。
public final class InputGuard {
    public var holdToAuthSeconds: Double = 2.0
    /// 两次物理 Esc 在这个窗口内按下时直接触发退出，不需要长按。
    public var doubleEscapeSeconds: Double = 0.7
    /// 幕帘期间的撤幕快捷键，必须和 GlobalHotkey 使用同一个绑定。
    public var exitHotkeyKeyCode: Int64 = HotkeyPolicy.keyCode
    public var exitHotkeyModifiers: CGEventFlags = HotkeyPolicy.modifiers
    public var onHoldEscape: (() -> Void)?
    /// 幕帘期间再次按起幕快捷键时调用。
    public var onExitHotkey: (() -> Void)?
    /// Touch ID 面板显示期间再次按物理 Esc 时取消认证。
    public var onCancelAuthentication: (() -> Void)?
    /// tap 被系统禁用且无法恢复时调用。调用方应尽快撤幕。
    public var onTapUnavailable: (() -> Void)?
    /// 幕帘期间检测到真实 HID 输入时调用。只用于低频界面提示，不参与授权。
    public var onPhysicalInteraction: (() -> Void)?

    private let lock = NSLock()
    private let interactionLock = NSLock()
    private var _isEnabled = false
    private var authenticationMode = false
    private var tap: CFMachPort?
    private var gestureTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureRunLoopSource: CFRunLoopSource?
    private var holdWorkItem: DispatchWorkItem?
    private var escDown = false
    private var escapeTap = DoubleEscapeRecognizer()
    private var failureReported = false
    private var reenableBreaker = ReenableCircuitBreaker()
    private var lastPhysicalInteractionAt: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }

    public var gesturesProtected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gestureTap != nil
    }

    @discardableResult
    public func start() -> Bool {
        lock.lock()
        let existingPrimary = tap
        let existingGesture = gestureTap
        lock.unlock()
        let existingReady: Bool
        if let existingPrimary, let existingGesture {
            existingReady = CGEvent.tapIsEnabled(tap: existingPrimary)
                && CGEvent.tapIsEnabled(tap: existingGesture)
        } else {
            existingReady = false
        }
        if existingReady { return true }

        stop()

        guard let primaryTap = makePrimaryTap() else { return false }
        guard let gestureTap = makeGestureTap() else {
            CFMachPortInvalidate(primaryTap)
            return false
        }
        guard let primarySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, primaryTap, 0),
              let gestureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gestureTap, 0) else {
            CFMachPortInvalidate(primaryTap)
            CFMachPortInvalidate(gestureTap)
            return false
        }

        lock.lock()
        self.tap = primaryTap
        self.gestureTap = gestureTap
        self.runLoopSource = primarySource
        self.gestureRunLoopSource = gestureSource
        failureReported = false
        reenableBreaker = ReenableCircuitBreaker()
        lock.unlock()

        CFRunLoopAddSource(CFRunLoopGetMain(), primarySource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        CGEvent.tapEnable(tap: primaryTap, enable: true)
        CGEvent.tapEnable(tap: gestureTap, enable: true)

        guard CGEvent.tapIsEnabled(tap: primaryTap), CGEvent.tapIsEnabled(tap: gestureTap) else {
            stop()
            return false
        }
        return true
    }

    public func setEnabled(_ on: Bool) {
        lock.lock()
        _isEnabled = on
        if !on { authenticationMode = false }
        lock.unlock()
        if !on {
            escDown = false
            escapeTap.reset()
            cancelHold()
        }
    }

    /// Touch ID 面板显示期间，物理键盘/鼠标仍被吞掉；Touch ID 使用独立硬件。
    /// 合成输入继续放行，避免误伤正在执行任务的 Agent。
    public func setAuthenticationMode(_ on: Bool) {
        lock.lock()
        authenticationMode = on
        lock.unlock()
        if on {
            escDown = false
            escapeTap.reset()
            cancelHold()
        }
    }

    /// 由后台 watchdog 定期调用。返回 false 表示至少一个 tap 已经无法恢复。
    public func healthCheck() -> Bool {
        lock.lock()
        let enabled = _isEnabled
        let primary = tap
        let gesture = gestureTap
        lock.unlock()

        guard enabled else { return true }
        guard let primary, let gesture else {
            reportUnavailable()
            return false
        }

        for tap in [primary, gesture] where !CGEvent.tapIsEnabled(tap: tap) {
            guard reenable(tap) else {
                reportUnavailable()
                return false
            }
        }
        let ok = CGEvent.tapIsEnabled(tap: primary) && CGEvent.tapIsEnabled(tap: gesture)
        if ok {
            resetFailure()
            lock.lock()
            _ = reenableBreaker.resetIfStable()
            lock.unlock()
        } else {
            reportUnavailable()
        }
        return ok
    }

    public func stop() {
        lock.lock()
        let primary = tap
        let gesture = gestureTap
        let primarySource = runLoopSource
        let gestureSource = gestureRunLoopSource
        tap = nil
        gestureTap = nil
        runLoopSource = nil
        gestureRunLoopSource = nil
        _isEnabled = false
        authenticationMode = false
        failureReported = false
        reenableBreaker = ReenableCircuitBreaker()
        lock.unlock()

        escDown = false
        escapeTap.reset()
        cancelHold()
        if let primary { CGEvent.tapEnable(tap: primary, enable: false) }
        if let gesture { CGEvent.tapEnable(tap: gesture, enable: false) }
        if let primarySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), primarySource, .commonModes)
        }
        if let gestureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        }
        if let primary { CFMachPortInvalidate(primary) }
        if let gesture { CFMachPortInvalidate(gesture) }
    }

    private func makePrimaryTap() -> CFMachPort? {
        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
            .tabletPointer, .tabletProximity,
        ]
        for type in types { mask |= (CGEventMask(1) << type.rawValue) }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guarder = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
                return guarder.handlePrimary(type: type, event: event)
            },
            userInfo: userInfo
        )
    }

    private func makeGestureTap() -> CFMachPort? {
        var mask: CGEventMask = 0
        for rawValue in InputPolicy.gestureEventRawValues {
            mask |= (CGEventMask(1) << rawValue)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guarder = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
                return guarder.handleGesture(type: type, event: event)
            },
            userInfo: userInfo
        )
    }

    private func handlePrimary(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenable(tap) {
                reportUnavailable()
            }
            return nil
        }

        let enabled = isEnabled
        let sourcePID = Int32(event.getIntegerValueField(.eventSourceUnixProcessID))
        let keyCode: Int64? = (type == .keyDown || type == .keyUp)
            ? event.getIntegerValueField(.keyboardEventKeycode)
            : nil
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let authenticationMode = isAuthenticationMode
        let flags = event.flags

        if enabled, sourcePID == 0, !authenticationMode, keyCode != 53 {
            notifyPhysicalInteraction()
        }

        if enabled, sourcePID == 0, let keyCode,
           type == .keyDown || type == .keyUp {
            if authenticationMode, keyCode == 53 {
                if type == .keyDown, !isRepeat {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCancelAuthentication?()
                    }
                }
                return nil
            }

            if !authenticationMode,
               HotkeyPolicy.matches(
                   eventKeyCode: keyCode,
                   flags: flags,
                   sourcePID: sourcePID,
                   expectedKeyCode: exitHotkeyKeyCode,
                   expectedModifiers: exitHotkeyModifiers
               ) {
                if type == .keyDown, !isRepeat {
                    DispatchQueue.main.async { [weak self] in
                        self?.onExitHotkey?()
                    }
                }
                return nil
            }

            if !authenticationMode, keyCode == 53, type == .keyDown, !isRepeat {
                if escapeTap.registerDown(window: doubleEscapeSeconds) {
                    escDown = false
                    cancelHold()
                    DispatchQueue.main.async { [weak self] in
                        self?.onHoldEscape?()
                    }
                    return nil
                }
            }
        }

        let disposition = InputPolicy.disposition(
            rawEventType: type.rawValue,
            keyCode: keyCode,
            isRepeat: isRepeat,
            sourcePID: sourcePID,
            isEnabled: enabled,
            authenticationMode: authenticationMode
        )

        switch disposition {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .block:
            return nil
        case .beginHold:
            if !escDown {
                escDown = true
                scheduleHold()
            }
            return nil
        case .cancelHold:
            escDown = false
            cancelHold()
            return nil
        }
    }

    private func handleGesture(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenable(gestureTap) {
                reportUnavailable()
            }
            return nil
        }
        guard isEnabled else { return Unmanaged.passUnretained(event) }
        return nil
    }

    private func reenable(_ target: CFMachPort?) -> Bool {
        guard let target else { return false }
        if !CGEvent.tapIsEnabled(tap: target) {
            lock.lock()
            if reenableBreaker.isTripped {
                lock.unlock()
                return false
            }
            let tripped = reenableBreaker.recordAttempt()
            lock.unlock()
            guard !tripped else { return false }
            CGEvent.tapEnable(tap: target, enable: true)
        }
        return CGEvent.tapIsEnabled(tap: target)
    }

    private func scheduleHold() {
        cancelHold()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled, self.escDown else { return }
            self.onHoldEscape?()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdToAuthSeconds, execute: item)
    }

    private func cancelHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    private func reportUnavailable() {
        lock.lock()
        let shouldReport = !failureReported
        failureReported = true
        lock.unlock()
        guard shouldReport else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTapUnavailable?()
        }
    }

    private func notifyPhysicalInteraction() {
        let now = ProcessInfo.processInfo.systemUptime
        interactionLock.lock()
        guard now - lastPhysicalInteractionAt >= 1 else {
            interactionLock.unlock()
            return
        }
        lastPhysicalInteractionAt = now
        interactionLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onPhysicalInteraction?()
        }
    }

    private func resetFailure() {
        lock.lock()
        failureReported = false
        lock.unlock()
    }

    private var isAuthenticationMode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return authenticationMode
    }
}
