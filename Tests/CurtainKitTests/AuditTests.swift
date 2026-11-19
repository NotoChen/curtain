import Foundation
import Testing
@testable import CurtainKit

@Suite("Audit")
struct AuditTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurtainAuditTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Negative tail count does not trap")
    func negativeTailCount() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("audit.log")
        let log = AuditLog(url: url)
        log.write("first")
        log.flush()

        #expect(log.tail(-1).isEmpty)
        #expect(log.tail(0).isEmpty)
        #expect(log.tail(1).count == 1)
    }

    @Test("Hashless record after hashed chain is rejected")
    func hashlessRecordAfterChain() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("audit.log")
        let log = AuditLog(url: url)
        log.write("first")
        log.write("second")
        log.flush()

        #expect(AuditLog.verify(url).ok)

        var forged = Data(#"{"event":"forged","prev":"","ts":"2026-01-01T00:00:00.000Z"}"#.utf8)
        forged.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: forged)
        try handle.close()

        let result = AuditLog.verify(url)
        #expect(!result.ok)
        #expect(result.brokenAtLine == 3)
    }

    @Test("Legacy records before a new chain are accepted")
    func legacyRecordBeforeNewChain() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("audit.log")
        let log = AuditLog(url: url)
        log.write("first")
        log.write("second")
        log.flush()

        var legacy = Data(#"{"event":"legacy","ts":"2026-01-01T00:00:00.000Z"}"#.utf8)
        legacy.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: legacy)
        try handle.close()

        let continuation = AuditLog(url: url)
        continuation.write("third")
        continuation.flush()

        let result = AuditLog.verify(url)
        #expect(result.ok)
        #expect(result.count == 3)
        #expect(result.legacy == 1)
    }

}
