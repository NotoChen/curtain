import Foundation

public struct ControlRequest: Codable {
    public var cmd: String
    public var out: String?
    public var display: Int?
    public var duration: Double?
    /// 截图是否包含鼠标指针
    public var cursor: Bool?
    /// 截图区域，"x,y,w,h"（点为单位，相对该屏左上角）
    public var region: String?
    /// 是否对全部显示器各截一张
    public var allDisplays: Bool?
    /// 录制帧率
    public var fps: Int?
    /// 录制码率（bps）
    public var bitrate: Int?

    public init(cmd: String, out: String? = nil, display: Int? = nil, duration: Double? = nil,
                cursor: Bool? = nil, region: String? = nil, allDisplays: Bool? = nil,
                fps: Int? = nil, bitrate: Int? = nil) {
        self.cmd = cmd
        self.out = out
        self.display = display
        self.duration = duration
        self.cursor = cursor
        self.region = region
        self.allDisplays = allDisplays
        self.fps = fps
        self.bitrate = bitrate
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
