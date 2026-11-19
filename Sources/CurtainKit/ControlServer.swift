import Darwin
import Foundation

public enum ControlError: Error, CustomStringConvertible {
    case socket(String)

    public var description: String {
        if case let .socket(message) = self { return message }
        return "control error"
    }
}

private let controlMaxRequestBytes = 64 * 1024
private let controlMaxResponseBytes = 16 * 1024 * 1024

private func makeSocketAddress(for path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else { return nil }
    _ = path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                strncpy(destination, source, capacity - 1)
            }
        }
    }
    return address
}

private func configureSocket(_ fd: Int32, receiveSeconds: Int, sendSeconds: Int) {
    var noSigPipe: Int32 = 1
    _ = setsockopt(
        fd,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSigPipe,
        socklen_t(MemoryLayout<Int32>.size)
    )

    var receiveTimeout = timeval(tv_sec: receiveSeconds, tv_usec: 0)
    _ = setsockopt(
        fd,
        SOL_SOCKET,
        SO_RCVTIMEO,
        &receiveTimeout,
        socklen_t(MemoryLayout<timeval>.size)
    )

    var sendTimeout = timeval(tv_sec: sendSeconds, tv_usec: 0)
    _ = setsockopt(
        fd,
        SOL_SOCKET,
        SO_SNDTIMEO,
        &sendTimeout,
        socklen_t(MemoryLayout<timeval>.size)
    )
}

private func readControlLine(fd: Int32, maxBytes: Int) -> Data? {
    var result = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while result.count < maxBytes {
        let count = read(fd, &chunk, chunk.count)
        if count < 0 {
            if errno == EINTR { continue }
            return nil
        }
        if count == 0 {
            return result.isEmpty ? nil : result
        }
        if let newline = chunk[0..<count].firstIndex(of: 0x0A) {
            result.append(contentsOf: chunk[0..<newline])
            return result
        }
        result.append(contentsOf: chunk[0..<count])
    }
    return nil
}

private func writeControlData(fd: Int32, data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return true }
        var offset = 0
        while offset < raw.count {
            let count = write(fd, base.advanced(by: offset), raw.count - offset)
            if count < 0 {
                if errno == EINTR { continue }
                return false
            }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
}

/// 极简 unix socket 服务：一行 JSON 请求，一行 JSON 响应，一次连接一条命令。
/// 只允许当前用户连接；命令本身仍按产品边界开放给同用户的本地进程。
public final class ControlServer {
    public typealias Handler = (ControlRequest, ProcessPeer?) -> ControlResponse
    public typealias LegacyHandler = (ControlRequest) -> ControlResponse

    private let path: String
    private var listenFD: Int32 = -1
    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "curtain.control.accept")
    private let clientQueue = DispatchQueue(
        label: "curtain.control.clients",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let clientSlots = DispatchSemaphore(value: 8)
    private var handler: Handler?

    public init(path: String = Paths.socketURL.path) {
        self.path = path
    }

    public func start(handler: @escaping Handler) throws {
        self.handler = handler
        try startServer()
    }

    public func start(handler: @escaping LegacyHandler) throws {
        try start { request, _ in handler(request) }
    }

    private func startServer() throws {
        guard Paths.ensureSupportDir() else {
            throw ControlError.socket("无法创建 \(Paths.supportDir.path)")
        }
        guard makeSocketAddress(for: path) != nil else {
            throw ControlError.socket("控制 socket 路径过长：\(path)")
        }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlError.socket("socket() 失败")
        }
        configureSocket(fd, receiveSeconds: 5, sendSeconds: 30)

        guard var address = makeSocketAddress(for: path) else {
            close(fd)
            throw ControlError.socket("控制 socket 路径过长：\(path)")
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, size)
            }
        }
        guard bound == 0 else {
            close(fd)
            throw ControlError.socket("bind(\(path)) 失败")
        }
        guard chmod(path, 0o600) == 0 else {
            close(fd)
            unlink(path)
            throw ControlError.socket("无法设置控制 socket 权限")
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            unlink(path)
            throw ControlError.socket("listen() 失败")
        }

        stateLock.lock()
        listenFD = fd
        stateLock.unlock()
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        stateLock.lock()
        let fd = listenFD
        listenFD = -1
        stateLock.unlock()

        if fd >= 0 {
            _ = shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        unlink(path)
    }

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let fd = listenFD
            stateLock.unlock()
            guard fd >= 0 else { return }

            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                stateLock.lock()
                let stopped = listenFD < 0
                stateLock.unlock()
                if stopped || errno == EBADF { return }
                usleep(10_000)
                continue
            }

            clientSlots.wait()
            let slots = clientSlots
            clientQueue.async { [weak self] in
                defer { slots.signal() }
                guard let self else {
                    close(client)
                    return
                }
                self.serve(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }

        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
            return
        }
        configureSocket(client, receiveSeconds: 5, sendSeconds: 30)

        guard let line = readControlLine(fd: client, maxBytes: controlMaxRequestBytes),
              let handler else { return }
        let request = (try? JSONDecoder().decode(ControlRequest.self, from: line))
            ?? ControlRequest(cmd: "invalid")
        let response = handler(request, ProcessPeerResolver.peerIdentity(fd: client))

        guard var output = try? JSONEncoder().encode(response) else { return }
        output.append(0x0A)
        _ = writeControlData(fd: client, data: output)
    }
}

public enum ControlClient {
    public static func send(
        _ request: ControlRequest,
        path: String = Paths.socketURL.path
    ) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.socket("socket() 失败") }
        defer { close(fd) }
        configureSocket(fd, receiveSeconds: 90, sendSeconds: 10)

        guard var address = makeSocketAddress(for: path) else {
            throw ControlError.socket("控制 socket 路径过长：\(path)")
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, size)
            }
        }
        guard connected == 0 else {
            throw ControlError.socket("连不上 curtaind（\(path)）。先启动 Curtain.app。")
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        guard writeControlData(fd: fd, data: payload) else {
            throw ControlError.socket("发送控制请求失败")
        }
        guard let response = readControlLine(fd: fd, maxBytes: controlMaxResponseBytes) else {
            throw ControlError.socket("没有收到响应")
        }
        return try JSONDecoder().decode(ControlResponse.self, from: response)
    }
}
