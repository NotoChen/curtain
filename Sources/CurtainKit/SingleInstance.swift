import Foundation

/// 单实例守卫：同一时刻只允许一个 curtaind 持有控制 socket。
/// 用 flock 而非 pid 文件——进程崩溃时内核自动释放，不会留下"幽灵锁"。
public final class SingleInstance {
    private var fd: Int32 = -1
    private let path: String

    public init(path: String = Paths.supportDir.appendingPathComponent("daemon.lock").path) {
        self.path = path
    }

    /// 返回 true 表示拿到锁（本进程是唯一实例）。
    public func acquire() -> Bool {
        Paths.ensureSupportDir()
        fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        let pid = "\(getpid())\n"
        _ = pid.withCString { ftruncate(fd, 0); write(fd, $0, strlen($0)) }
        return true
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { release() }
}
