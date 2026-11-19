import CoreGraphics
import Foundation
import Testing
@testable import CurtainKit

@Suite("Input policy")
struct InputPolicyTests {
    @Test("Physical keyboard and mouse are blocked")
    func physicalInputIsBlocked() {
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 0,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true
        ) == .block)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true
        ) == .block)
    }

    @Test("Synthetic input passes through")
    func syntheticInputPasses() {
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 0,
            isRepeat: false,
            sourcePID: 4242,
            isEnabled: true
        ) == .pass)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil,
            isRepeat: false,
            sourcePID: 4242,
            isEnabled: true
        ) == .pass)
    }

    @Test("Touch ID hold only starts from a physical Esc down")
    func escapeHoldIsPhysicalOnly() {
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 53,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true
        ) == .beginHold)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 53,
            isRepeat: true,
            sourcePID: 0,
            isEnabled: true
        ) == .block)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyUp.rawValue,
            keyCode: 53,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true
        ) == .cancelHold)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 53,
            isRepeat: false,
            sourcePID: 4242,
            isEnabled: true
        ) == .pass)
    }

    @Test("System gesture stream is blocked while enabled")
    func gesturesAreBlocked() {
        #expect(InputPolicy.disposition(
            rawEventType: 30,
            keyCode: nil,
            isRepeat: false,
            sourcePID: 4242,
            isEnabled: true
        ) == .block)
    }

    @Test("Authentication mode blocks physical input but leaves synthetic input alone")
    func authenticationModeBlocksPhysicalInput() {
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 0,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true,
            authenticationMode: true
        ) == .block)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true,
            authenticationMode: true
        ) == .block)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyUp.rawValue,
            keyCode: 53,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true,
            authenticationMode: true
        ) == .block)
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 0,
            isRepeat: false,
            sourcePID: 4242,
            isEnabled: true,
            authenticationMode: true
        ) == .pass)
        #expect(InputPolicy.disposition(
            rawEventType: 30,
            keyCode: nil,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: true,
            authenticationMode: true
        ) == .block)
    }

    @Test("Disabled guard passes everything")
    func disabledGuardPasses() {
        #expect(InputPolicy.disposition(
            rawEventType: CGEventType.keyDown.rawValue,
            keyCode: 0,
            isRepeat: false,
            sourcePID: 0,
            isEnabled: false
        ) == .pass)
    }
}

@Suite("Curtain state")
struct CurtainStateTests {
    @Test("Only active and authenticating states are on")
    func onStates() {
        #expect(!CurtainState.idle.isOn)
        #expect(CurtainState.active.isOn)
        #expect(CurtainState.authenticating.isOn)
        #expect(!CurtainState.active.isAuthenticating)
        #expect(CurtainState.authenticating.isAuthenticating)
    }
}

@Suite("Escape exit gesture")
struct DoubleEscapeRecognizerTests {
    @Test("Two presses inside the window trigger once")
    func doublePressFires() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        let second = recognizer.registerDown(at: start.addingTimeInterval(0.5), window: 0.7)
        #expect(second)
        let third = recognizer.registerDown(at: start.addingTimeInterval(1.0), window: 0.7)
        #expect(!third)
    }

    @Test("A slow second press starts a new window")
    func slowPressDoesNotFire() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        let second = recognizer.registerDown(at: start.addingTimeInterval(0.8), window: 0.7)
        #expect(!second)
        let third = recognizer.registerDown(at: start.addingTimeInterval(1.2), window: 0.7)
        #expect(third)
    }

    @Test("Reset discards the pending first press")
    func resetDiscards() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        recognizer.reset()
        let afterReset = recognizer.registerDown(at: start.addingTimeInterval(0.2), window: 0.7)
        #expect(!afterReset)
    }
}

@Suite("Global hotkey")
struct GlobalHotkeyTests {
    @Test("Only physical ctrl-option-command-C matches")
    func hotkeyMatching() {
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        #expect(HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers,
            sourcePID: 0
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers,
            sourcePID: 4242
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: [.maskControl, .maskCommand],
            sourcePID: 0
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers.union(.maskShift),
            sourcePID: 0
        ))
    }

    @Test("Custom binding matches only its own key and modifiers")
    func customBindingMatching() {
        let custom: CGEventFlags = [.maskControl, .maskShift]
        #expect(HotkeyPolicy.matches(
            eventKeyCode: 1,
            flags: custom,
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: 1,
            flags: [.maskControl, .maskShift, .maskAlternate],
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: HotkeyPolicy.modifiers,
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
    }

    @Test("Binding validation requires a normal key and a non-shift modifier")
    func bindingValidation() {
        #expect(HotkeyBinding(keyCode: 8, modifiers: [.maskCommand]).isValid)
        #expect(!HotkeyBinding(keyCode: 8, modifiers: [.maskShift]).isValid)
        #expect(!HotkeyBinding(keyCode: 8, modifiers: []).isValid)
        #expect(!HotkeyBinding(keyCode: 999, modifiers: [.maskCommand]).isValid)
    }

    @Test("Display string is stable")
    func displayString() {
        #expect(HotkeyPolicy.displayString(
            keyCode: HotkeyPolicy.keyCode,
            modifiers: HotkeyPolicy.modifiers
        ) == "⌃⌥⌘C")
    }
}

@Suite("Event tap recovery")
struct ReenableCircuitBreakerTests {
    @Test("Five rapid re-enables trip the breaker")
    func tripsAfterRepeatedFailures() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        for index in 0..<4 {
            let tripped = breaker.recordAttempt(at: start.addingTimeInterval(Double(index) * 0.5))
            #expect(!tripped)
        }
        let tripped = breaker.recordAttempt(at: start.addingTimeInterval(2))
        #expect(tripped)
        #expect(breaker.isTripped)
    }

    @Test("A slow re-enable outside the window starts a fresh count")
    func oldFailuresDoNotAccumulate() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        var tripped = breaker.recordAttempt(at: start)
        #expect(!tripped)
        tripped = breaker.recordAttempt(at: start.addingTimeInterval(11))
        #expect(!tripped)
        tripped = breaker.recordAttempt(at: start.addingTimeInterval(22))
        #expect(!tripped)
        #expect(!breaker.isTripped)
    }

    @Test("A long stable period resets a tripped breaker")
    func stablePeriodResetsBreaker() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        for _ in 0..<5 {
            _ = breaker.recordAttempt(at: start)
        }
        #expect(breaker.isTripped)
        var reset = breaker.resetIfStable(at: start.addingTimeInterval(29))
        #expect(!reset)
        reset = breaker.resetIfStable(at: start.addingTimeInterval(31))
        #expect(reset)
        #expect(!breaker.isTripped)
    }
}
