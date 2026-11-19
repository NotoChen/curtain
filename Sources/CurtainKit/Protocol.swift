import Foundation

public struct ControlRequest: Codable {
    public var cmd: String
    public var out: String?
    public var display: Int?
    /// 稳定的 CGDirectDisplayID；优先于 `display` 下标。
    public var displayID: UInt32?
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
    /// 调用方自报的 Agent/任务标识，只用于活动记录，不参与授权。
    public var client: String?
    /// 本次保护时长（分钟）；0 表示不自动请求退出。
    public var minutes: Int?
    /// 场景预设标识，见 CurtainScene.rawValue。
    public var scene: String?

    public init(cmd: String, out: String? = nil, display: Int? = nil, displayID: UInt32? = nil,
                duration: Double? = nil,
                cursor: Bool? = nil, region: String? = nil, allDisplays: Bool? = nil,
                fps: Int? = nil, bitrate: Int? = nil, client: String? = nil,
                minutes: Int? = nil, scene: String? = nil) {
        self.cmd = cmd
        self.out = out
        self.display = display
        self.displayID = displayID
        self.duration = duration
        self.cursor = cursor
        self.region = region
        self.allDisplays = allDisplays
        self.fps = fps
        self.bitrate = bitrate
        self.client = client
        self.minutes = minutes
        self.scene = scene
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
