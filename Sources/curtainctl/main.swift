import CurtainKit
import Foundation

func usage() -> Never {
    print("""
    curtainctl — 控制 Curtain 幕帘

      curtainctl on                          升起幕帘（黑屏 + 拦截物理输入）
      curtainctl off                         请求解除（长按 Esc 或走 Touch ID）
      curtainctl status                      查看状态
      curtainctl capture [--out PATH] [--display N]
                                             截取完整桌面（画面中不含幕帘）
      curtainctl record start [--out PATH] [--display N]
      curtainctl record stop
      curtainctl audit [N]                   最近 N 条审计（默认 20）

    返回值为 JSON；失败时退出码 1。
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

let request: ControlRequest
switch command {
case "on":
    request = ControlRequest(cmd: "on")
case "off":
    request = ControlRequest(cmd: "off")
case "status":
    request = ControlRequest(cmd: "status")
case "capture":
    request = ControlRequest(cmd: "capture", out: value(for: "--out"), display: value(for: "--display").flatMap(Int.init))
case "record":
    guard let action = args.first else { usage() }
    if action == "start" {
        request = ControlRequest(cmd: "record_start", out: value(for: "--out"), display: value(for: "--display").flatMap(Int.init))
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
