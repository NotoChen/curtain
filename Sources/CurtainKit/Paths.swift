import Foundation

/// 固定路径：全部落在 ~/Library/Application Support/Curtain 下。
public enum Paths {
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Curtain", isDirectory: true)
    }

    public static var socketURL: URL { supportDir.appendingPathComponent("control.sock") }
    public static var configURL: URL { supportDir.appendingPathComponent("config.json") }
    public static var auditURL: URL { supportDir.appendingPathComponent("audit.log") }

    @discardableResult
    public static func ensureSupportDir() -> Bool {
        (try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)) != nil
    }
}
