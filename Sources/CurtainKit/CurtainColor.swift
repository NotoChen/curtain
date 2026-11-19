import Foundation

/// 输出层幕帘只能做整屏纯色。gamma 表没有空间信息，图片和文字必须进入
/// framebuffer，而那会被 Agent 的截图/录屏看到。
public struct CurtainColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255.0,
            green: Double((number >> 8) & 0xFF) / 255.0,
            blue: Double(number & 0xFF) / 255.0
        )
    }

    public var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public var isBlack: Bool {
        red <= 0.001 && green <= 0.001 && blue <= 0.001
    }

    public static let black = CurtainColor(red: 0, green: 0, blue: 0)
}
