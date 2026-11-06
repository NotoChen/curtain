import CurtainKit
import Foundation

func usage() -> Never {
    print("""
    curtainctl — 控制 Curtain 幕帘

      curtainctl on                            升起幕帘（黑屏 + 拦截物理输入）
      curtainctl off                           请求解除（长按 Esc 或走 Touch ID）
      curtainctl panic                         应急强制撤幕（不验指纹，需本地 shell）
      curtainctl status                        查看状态（JSON）
      curtainctl doctor                        自检：权限 / 屏 / tap / 审计链 / 自启

      curtainctl capture [--out PATH] [--display N] [--all] [--cursor] [--region x,y,w,h]
                                               截取桌面（画面中不含幕帘）；--all 每屏一张
      curtainctl record start [--out PATH] [--display N] [--fps 30] [--bitrate 8000000]
      curtainctl record stop

      curtainctl audit [N]                     最近 N 条审计（默认 20）
      curtainctl audit --verify                校验审计哈希链

      curtainctl install-agent                 安装开机自启（LaunchAgent）
      curtainctl uninstall-agent               移除开机自启
      curtainctl agent-status                  查看自启状态

    远端命令返回 JSON；失败时退出码 1。doctor 输出为纯文本。
    """)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()

func value(for flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else { return nil }
    return args[args.index(after: index)]
}

func hasFlag(_ flag: String) -> Bool { args.contains(flag) }

func daemonPath() -> String {
    let installed = "/Applications/Curtain.app/Contents/MacOS/curtaind"
    if FileManager.default.isExecutableFile(atPath: installed) { return installed }
    let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("curtaind").path
    if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
    return installed
}

/// 本地命令（不需要 curtaind 在跑）
switch command {
case "install-agent":
    if let error = LaunchAgent.install(executable: daemonPath()) {
        FileHandle.standardError.write(Data("安装失败：\(error)\n".utf8))
        exit(1)
    }
    print("已安装开机自启：\(LaunchAgent.plistURL.path)")
    print("程序：\(daemonPath())")
    exit(0)
case "uninstall-agent":
    if let error = LaunchAgent.uninstall() {
        FileHandle.standardError.write(Data("移除失败：\(error)\n".utf8))
        exit(1)
    }
    print("已移除开机自启")
    exit(0)
case "agent-status":
    let status = LaunchAgent.status()
    print("plist：\(status.installed ? "已安装" : "未安装")  \(LaunchAgent.plistURL.path)")
    print("launchd：\(status.loaded ? "已加载" : "未加载")")
    if let exe = status.executablePath { print("程序：\(exe)") }
    exit(0)
case "audit" where hasFlag("--verify"):
    let result = AuditLog.verify()
    if result.ok {
        print("审计链完整：\(result.count) 条")
        exit(0)
    }
    print("审计链断裂：第 \(result.brokenAtLine ?? -1) 行，\(result.reason ?? "")")
    exit(1)
default:
    break
}

let request: ControlRequest
switch command {
case "on":
    request = ControlRequest(cmd: "on")
case "off":
    request = ControlRequest(cmd: "off")
case "status":
    request = ControlRequest(cmd: "status")
case "doctor":
    request = ControlRequest(cmd: "doctor")
case "panic":
    request = ControlRequest(cmd: "panic")
case "capture":
    let displayArg = value(for: "--display")
    let all = hasFlag("--all") || displayArg == "all"
    request = ControlRequest(
        cmd: "capture",
        out: value(for: "--out"),
        display: displayArg.flatMap(Int.init),
        cursor: hasFlag("--cursor"),
        region: value(for: "--region"),
        allDisplays: all
    )
case "record":
    guard let action = args.first else { usage() }
    if action == "start" {
        request = ControlRequest(
            cmd: "record_start",
            out: value(for: "--out"),
            display: value(for: "--display").flatMap(Int.init),
            fps: value(for: "--fps").flatMap(Int.init),
            bitrate: value(for: "--bitrate").flatMap(Int.init)
        )
    } else if action == "stop" {
        request = ControlRequest(cmd: "record_stop")
    } else {
        usage()
    }
case "audit":
    let count = args.first.flatMap(Int.init) ?? 20
    request = ControlRequest(cmd: "audit", display: count)
case "-h", "--help", "help":
    usage()
default:
    usage()
}

do {
    let response = try ControlClient.send(request)
    if command == "doctor" {
        print(response.message)
        exit(response.ok ? 0 : 1)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(response.ok ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("curtainctl: \(error)\n".utf8))
    exit(1)
}
