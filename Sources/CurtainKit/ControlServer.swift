import Darwin
import Foundation

public enum ControlError: Error, CustomStringConvertible {
    case socket(String)

    public var description: String {
        if case let .socket(message) = self { return message }
        return "control error"
    }
}

/// 极简 unix socket 服务：一行 JSON 请求，一行 JSON 响应，一次连接一条命令。
public final class ControlServer {
    public typealias Handler = (ControlRequest) -> ControlResponse

    private let path: String
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "curtain.control.accept")
    private var handler: Handler?

    public init(path: String = Paths.socketURL.path) {
        self.path = path
    }

    public func start(handler: @escaping Handler) throws {
        self.handler = handler
        Paths.ensureSupportDir()
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.socket("socket() 失败") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                    strncpy(dst, cs, pathCapacity - 1)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            close(fd)
            throw ControlError.socket("bind(\(path)) 失败")
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw ControlError.socket("listen() 失败")
        }
        listenFD = fd
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                usleep(10_000)
                continue
            }
            DispatchQueue.global().async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = read(client, &buffer, buffer.count)
        guard count > 0, let handler else { return }

        let data = Data(buffer[0..<count])
        let line = data.split(separator: 0x0A).first.map(Data.init) ?? data
        let request = (try? JSONDecoder().decode(ControlRequest.self, from: line)) ?? ControlRequest(cmd: "invalid")
        let response = handler(request)

        guard var out = try? JSONEncoder().encode(response) else { return }
        out.append(0x0A)
        _ = out.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}

public enum ControlClient {
    public static func send(_ request: ControlRequest) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.socket("socket() 失败") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Paths.socketURL.path
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                    strncpy(dst, cs, pathCapacity - 1)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else {
            throw ControlError.socket("连不上 curtaind（\(path)）。先启动 Curtain.app。")
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { throw ControlError.socket("没有收到响应") }
        return try JSONDecoder().decode(ControlResponse.self, from: Data(buffer[0..<count]))
    }
}
