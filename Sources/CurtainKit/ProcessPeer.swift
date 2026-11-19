import AppKit
import Darwin
import Foundation

public struct ProcessDescriptor: Equatable {
    public let pid: Int32
    public let name: String
    public let executablePath: String
    public let bundleIdentifier: String?

    public init(pid: Int32,
                name: String,
                executablePath: String,
                bundleIdentifier: String? = nil) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
    }
}

/// The process at the other end of the local control socket, plus a short
/// ancestor chain. The daemon receives `curtainctl`, but the useful caller is
/// usually its parent agent (Codex, Claude Code, a shell, or a test runner).
public struct ProcessPeer: Equatable {
    public let direct: ProcessDescriptor
    public let principal: ProcessDescriptor
    public let ancestors: [ProcessDescriptor]
    public let environmentHint: String?

    public init(direct: ProcessDescriptor,
                principal: ProcessDescriptor,
                ancestors: [ProcessDescriptor],
                environmentHint: String? = nil) {
        self.direct = direct
        self.principal = principal
        self.ancestors = ancestors
        self.environmentHint = environmentHint
    }

    public var displayName: String {
        let processName = principal.name
        guard let environmentHint,
              environmentHint.caseInsensitiveCompare(processName) != .orderedSame else {
            return processName
        }
        if ProcessPeerResolver.isTransient(processName) {
            return environmentHint
        }
        return "\(environmentHint)（\(processName)）"
    }

    public var chainText: String {
        ancestors.map(\.name).joined(separator: " → ")
    }

    public var pidChain: String {
        ancestors.map { "\($0.pid)" }.joined(separator: ",")
    }
}

public enum ProcessPeerResolver {
    private static let shellNames: Set<String> = [
        "arch", "bash", "csh", "dash", "env", "fish", "ksh", "login",
        "rbash", "sh", "sudo", "tcsh", "zsh",
    ]
    private static let infrastructureNames: Set<String> = [
        "curtainctl", "init", "launchd",
    ]

    public static func peerIdentity(fd: Int32) -> ProcessPeer? {
        guard let pid = peerPID(fd: fd) else { return nil }
        return identity(for: pid)
    }

    public static func peerPID(fd: Int32) -> Int32? {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        let result = getsockopt(
            fd,
            SOL_LOCAL,
            LOCAL_PEERPID,
            &pid,
            &length
        )
        return result == 0 && pid > 0 ? pid : nil
    }

    public static func identity(for pid: Int32) -> ProcessPeer? {
        var chain: [ProcessDescriptor] = []
        var current = pid
        var seen = Set<Int32>()
        for _ in 0..<8 {
            guard current > 1,
                  !seen.contains(current),
                  let descriptor = descriptor(for: current) else { break }
            seen.insert(current)
            chain.append(descriptor)
            guard let parent = parentPID(of: current) else { break }
            current = parent
        }
        guard let direct = chain.first else { return nil }

        let principal = chain.first { descriptor in
            !isTransient(descriptor.name)
        } ?? chain.first { descriptor in
            descriptor.name.caseInsensitiveCompare("curtainctl") != .orderedSame
        } ?? direct
        let environmentHint = ProcessEnvironmentHints.displayName(
            from: ProcessEnvironment.values(for: direct.pid)
        )

        return ProcessPeer(
            direct: direct,
            principal: principal,
            ancestors: chain,
            environmentHint: environmentHint
        )
    }

    static func isTransient(_ processName: String) -> Bool {
        let name = processName.lowercased()
        return shellNames.contains(name) || infrastructureNames.contains(name)
    }

    private static func descriptor(for pid: Int32) -> ProcessDescriptor? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        let url = URL(fileURLWithPath: path)
        let running = NSRunningApplication(processIdentifier: pid)
        let name = running?.localizedName
            ?? url.deletingPathExtension().lastPathComponent
        return ProcessDescriptor(
            pid: pid,
            name: name.isEmpty ? url.lastPathComponent : name,
            executablePath: path,
            bundleIdentifier: running?.bundleIdentifier
        )
    }

    private static func parentPID(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(
                pointer.baseAddress,
                u_int(pointer.count),
                &info,
                &size,
                nil,
                0
            )
        }
        guard result == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}

enum ProcessEnvironment {
    static func values(for pid: Int32) -> [String: String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size,
              size <= 2 * 1024 * 1024 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { raw in
            sysctl(
                &mib,
                u_int(mib.count),
                raw.baseAddress,
                &size,
                nil,
                0
            )
        }
        guard result == 0, size > MemoryLayout<Int32>.size else { return [:] }
        buffer.removeSubrange(size..<buffer.count)

        let argc = buffer.withUnsafeBytes { raw in
            Int(raw.loadUnaligned(fromByteOffset: 0, as: Int32.self))
        }
        guard argc >= 0 else { return [:] }

        var offset = MemoryLayout<Int32>.size
        skipString(in: buffer, offset: &offset)
        while offset < buffer.count, buffer[offset] == 0 {
            offset += 1
        }
        for _ in 0..<argc where offset < buffer.count {
            skipString(in: buffer, offset: &offset)
        }

        var environment: [String: String] = [:]
        while offset < buffer.count {
            let start = offset
            skipString(in: buffer, offset: &offset)
            guard offset > start,
                  let entry = String(
                    bytes: buffer[start..<offset],
                    encoding: .utf8
                  ),
                  let separator = entry.firstIndex(of: "=") else {
                offset += 1
                continue
            }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            if !key.isEmpty {
                environment[key] = value
            }
            offset += 1
        }
        return environment
    }

    private static func skipString(in buffer: [UInt8], offset: inout Int) {
        while offset < buffer.count, buffer[offset] != 0 {
            offset += 1
        }
    }
}

enum ProcessEnvironmentHints {
    static func displayName(from environment: [String: String]) -> String? {
        if environment["CODEX_THREAD_ID"] != nil
            || environment["CODEX_SESSION_ID"] != nil {
            return "Codex"
        }
        if environment["CLAUDECODE"] == "1"
            || environment["CLAUDE_CODE_SESSION_ID"] != nil
            || environment["CLAUDE_CODE_ENTRYPOINT"] != nil {
            return "Claude"
        }
        if environment["CURSOR_TRACE_ID"] != nil {
            return "Cursor"
        }
        if environment["GEMINI_CLI"] != nil {
            return "Gemini CLI"
        }
        if environment["OPENCODE"] != nil {
            return "OpenCode"
        }
        if environment["T3CODE_THREAD_ID"] != nil {
            return "T3 Code"
        }
        if let terminal = terminalName(from: environment) {
            return terminal
        }
        return nil
    }

    private static func terminalName(from environment: [String: String]) -> String? {
        let termProgram = environment["TERM_PROGRAM"]?.lowercased()
        switch termProgram {
        case "apple_terminal": return "Terminal"
        case "iterm.app": return "iTerm"
        case "warpterminal": return "Warp"
        case "vscode": return "VS Code"
        case "wezterm": return "WezTerm"
        case "ghostty": return "Ghostty"
        case "hyper": return "Hyper"
        default: break
        }

        let bundle = environment["__CFBundleIdentifier"]?.lowercased()
        switch bundle {
        case "com.apple.terminal": return "Terminal"
        case "com.googlecode.iterm2": return "iTerm"
        case "dev.warp.warp-stable": return "Warp"
        case "com.microsoft.vscode": return "VS Code"
        case "com.mitchellh.ghostty": return "Ghostty"
        default: return nil
        }
    }
}

public enum CallerAttribution {
    public static func displayName(peer: ProcessPeer?, label: String?) -> String? {
        let label = normalized(label)
        let caller = normalized(peer?.displayName)
        switch (caller, label) {
        case let (caller?, label?) where caller.caseInsensitiveCompare(label) == .orderedSame:
            return caller
        case let (caller?, label?):
            return "\(caller)（\(label)）"
        case let (caller?, nil):
            return caller
        case let (nil, label?):
            return label
        case (nil, nil):
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
