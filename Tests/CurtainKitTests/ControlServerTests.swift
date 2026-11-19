import Foundation
import Darwin
import Testing
@testable import CurtainKit

@Suite("Control server")
struct ControlServerTests {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("curtain-control-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Framed request and large response")
    func framedRequestAndLargeResponse() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketPath = directory.appendingPathComponent("control.sock").path
        let server = ControlServer(path: socketPath)
        defer { server.stop() }
        let payload = String(repeating: "x", count: 100_000)
        try server.start { request in
            ControlResponse(ok: true, message: payload, data: ["cmd": request.cmd])
        }

        let response = try ControlClient.send(
            ControlRequest(cmd: "status"),
            path: socketPath
        )
        #expect(response.ok)
        #expect(response.message.count == payload.count)
        #expect((response.data?["cmd"] ?? "") == "status")
    }

    @Test("Missing control server returns an error")
    func missingServerReturnsError() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketPath = directory.appendingPathComponent("missing.sock").path
        var threw = false
        do {
            _ = try ControlClient.send(ControlRequest(cmd: "status"), path: socketPath)
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test("Control server resolves the real peer process")
    func peerProcess() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketPath = directory.appendingPathComponent("peer.sock").path
        let server = ControlServer(path: socketPath)
        defer { server.stop() }
        let box = PeerBox()
        try server.start { request, peer in
            box.peer = peer
            return ControlResponse(ok: true, message: request.cmd)
        }

        let response = try ControlClient.send(
            ControlRequest(cmd: "status"),
            path: socketPath
        )
        #expect(response.ok)
        let peer = box.peer
        #expect(peer?.direct.pid == getpid())
        #expect(!(peer?.principal.executablePath.isEmpty ?? true))
    }

    @Test("An external process is attributed through the socket")
    func externalPeerProcess() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketPath = directory.appendingPathComponent("external.sock").path
        let server = ControlServer(path: socketPath)
        defer { server.stop() }
        let box = PeerBox()
        try server.start { request, peer in
            box.peer = peer
            return ControlResponse(ok: true, message: request.cmd)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-U", socketPath]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data("{\"cmd\":\"status\"}\n".utf8))
        try input.fileHandleForWriting.close()

        let response = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(data: response, encoding: .utf8)?.contains("\"ok\"") == true)

        let peer = box.waitForPeer()
        #expect(peer?.direct.name.lowercased().contains("nc") == true)
        #expect(peer?.direct.executablePath.hasSuffix("/nc") == true)
        #expect((peer?.ancestors.count ?? 0) >= 1)
    }

    @Test("Unix socket peer PID is readable")
    func socketPeerPID() {
        var fds: [Int32] = [-1, -1]
        let result = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        #expect(result == 0)
        guard result == 0 else { return }
        defer {
            close(fds[0])
            close(fds[1])
        }
        #expect(ProcessPeerResolver.peerPID(fd: fds[0]) == getpid())
    }

    @Test("Caller label and process name are combined only when different")
    func callerAttribution() {
        let descriptor = ProcessDescriptor(
            pid: 42,
            name: "codex",
            executablePath: "/usr/local/bin/codex"
        )
        let peer = ProcessPeer(
            direct: descriptor,
            principal: descriptor,
            ancestors: [descriptor]
        )
        #expect(CallerAttribution.displayName(peer: peer, label: "codex") == "codex")
        #expect(CallerAttribution.displayName(peer: peer, label: "任务 A") == "codex（任务 A）")
        #expect(CallerAttribution.displayName(peer: nil, label: "任务 A") == "任务 A")
        #expect(CallerAttribution.displayName(peer: nil, label: nil) == nil)
    }

    @Test("Process environment is parsed for the current process")
    func processEnvironment() {
        let environment = ProcessEnvironment.values(for: getpid())
        #expect(environment["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(environment["PATH"] == ProcessInfo.processInfo.environment["PATH"])
    }

    @Test("Known agent environment becomes a caller hint")
    func environmentHint() {
        #expect(
            ProcessEnvironmentHints.displayName(
                from: ["CODEX_THREAD_ID": "thread"]
            ) == "Codex"
        )
        #expect(
            ProcessEnvironmentHints.displayName(
                from: ["CLAUDECODE": "1"]
            ) == "Claude"
        )
        #expect(
            ProcessEnvironmentHints.displayName(
                from: ["TERM_PROGRAM": "WarpTerminal"]
            ) == "Warp"
        )
        #expect(
            ProcessEnvironmentHints.displayName(
                from: ["CLAUDE_AGENT_SDK_VERSION": "0.3"]
            ) == nil
        )
    }

    @Test("Transient principal is replaced by the environment hint")
    func transientPrincipalUsesEnvironmentHint() {
        let shell = ProcessDescriptor(
            pid: 43,
            name: "zsh",
            executablePath: "/bin/zsh"
        )
        let peer = ProcessPeer(
            direct: shell,
            principal: shell,
            ancestors: [shell],
            environmentHint: "Codex"
        )
        #expect(peer.displayName == "Codex")
    }
}

private final class PeerBox: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var stored: ProcessPeer?

    var peer: ProcessPeer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
            ready.signal()
        }
    }

    func waitForPeer() -> ProcessPeer? {
        _ = ready.wait(timeout: .now() + 2)
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
