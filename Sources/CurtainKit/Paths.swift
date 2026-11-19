import Foundation

/// 固定路径：全部落在 ~/Library/Application Support/Curtain 下。
public enum Paths {
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Curtain", isDirectory: true)
    }

    public static var socketURL: URL {
        if let override = ProcessInfo.processInfo.environment["CURTAIN_CONTROL_SOCKET"],
           override.hasPrefix("/") {
            return URL(fileURLWithPath: override)
        }
        return supportDir.appendingPathComponent("control.sock")
    }
    public static var configURL: URL { supportDir.appendingPathComponent("config.json") }
    public static var auditURL: URL { supportDir.appendingPathComponent("audit.log") }

    @discardableResult
    public static func ensureSupportDir() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: supportDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: supportDir.path
            )
            return true
        } catch {
            return false
        }
    }
}
