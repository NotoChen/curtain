import Foundation

/// 开机自启用 LaunchAgent。
/// 写成 gui/<uid> 域的 LaunchAgent，KeepAlive 顺带当崩溃看门狗。
public enum LaunchAgent {
    public static let label = "com.wangsenhao.curtain"

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public struct Status {
        public let installed: Bool
        public let loaded: Bool
        public let executablePath: String?
    }

    public static func status() -> Status {
        Status(installed: FileManager.default.fileExists(atPath: plistURL.path),
               loaded: isLoaded(),
               executablePath: installedExecutable())
    }

    private static func isLoaded() -> Bool {
        runLaunchctl(["print", "gui/\(getuid())/\(label)"]) == nil
    }

    /// bootstrap/bootout 是异步的，读状态前给它一点时间收敛。
    private static func waitLoaded(_ want: Bool, timeout: TimeInterval = 1.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isLoaded() == want { return true }
            usleep(100_000)
        }
        return isLoaded() == want
    }

    /// 安装/更新并立即加载。executable 默认取当前可执行文件。
    @discardableResult
    public static func install(executable: String = CommandLine.arguments[0]) -> String? {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "StandardOutPath": Paths.supportDir.appendingPathComponent("launchd.out.log").path,
            "StandardErrorPath": Paths.supportDir.appendingPathComponent("launchd.err.log").path,
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
        } catch {
            return "写入 \(plistURL.path) 失败：\(error)"
        }

        // 先卸载旧定义，避免 bootstrap 报 already bootstrapped
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        if let error = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) {
            return "launchctl bootstrap 失败：\(error)"
        }
        _ = waitLoaded(true)
        return nil
    }

    @discardableResult
    public static func uninstall() -> String? {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        _ = waitLoaded(false)
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return nil
        } catch {
            return "删除 \(plistURL.path) 失败：\(error)"
        }
    }

    private static func installedExecutable() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return nil }
        return args.first
    }

    /// 执行 launchctl，成功返回 nil，失败返回错误输出。
    private static func runLaunchctl(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "\(error)"
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return process.terminationStatus == 0 ? nil : output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
