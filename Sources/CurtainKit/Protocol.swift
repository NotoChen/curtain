import Foundation

public struct ControlRequest: Codable {
    public var cmd: String
    public var out: String?
    public var display: Int?
    public var duration: Double?

    public init(cmd: String, out: String? = nil, display: Int? = nil, duration: Double? = nil) {
        self.cmd = cmd
        self.out = out
        self.display = display
        self.duration = duration
    }
}

public struct ControlResponse: Codable {
    public var ok: Bool
    public var message: String
    public var data: [String: String]?

    public init(ok: Bool, message: String, data: [String: String]? = nil) {
        self.ok = ok
        self.message = message
        self.data = data
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, message: message)
    }
}
