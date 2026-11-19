import AppKit
import CurtainKit

/// 点击后进入录制态，按下「修饰键 + 普通键」即完成绑定。
/// 只接受至少包含 Control / Option / Command 之一的组合，避免和普通输入冲突。
final class HotkeyRecorderButton: NSButton {
    var onCapture: ((HotkeyBinding) -> Void)?

    var binding: HotkeyBinding {
        didSet { updateTitle() }
    }
    private var isRecording = false

    init(binding: HotkeyBinding) {
        self.binding = binding
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            return
        }
        guard !isModifierOnly(event.keyCode) else { return }

        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let candidate = HotkeyBinding(keyCode: Int64(event.keyCode), modifiers: flags)
        guard candidate.isValid else {
            NSSound.beep()
            title = "需要 ⌃ / ⌥ / ⌘"
            applyStyle()
            return
        }

        isRecording = false
        binding = candidate
        updateTitle()
        onCapture?(candidate)
        window?.makeFirstResponder(nil)
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "请按组合键…"
        applyStyle()
        window?.makeFirstResponder(self)
    }

    private func updateTitle() {
        title = HotkeyPolicy.displayString(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        )
        applyStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    override func highlight(_ flag: Bool) {
        alphaValue = flag ? 0.74 : 1
    }

    private func applyStyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let foreground = isRecording ? CurtainTheme.accent : CurtainTheme.ink
            let border = isRecording
                ? CurtainTheme.accent.withAlphaComponent(0.52)
                : CurtainTheme.border
            layer?.backgroundColor = CurtainTheme.field.cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = border.cgColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph,
                ]
            )
        }
    }

    private func isModifierOnly(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}
