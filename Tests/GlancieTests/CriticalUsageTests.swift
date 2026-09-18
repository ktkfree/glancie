import XCTest
@testable import Glancie

final class CriticalUsageTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    // The per-adapter failure matrix that used to live here — HTTP statuses,
    // malformed bodies, timeouts, an empty key file, a rate limit sparing the
    // last reading — now lives in UsageFailureStateTests, which runs the same
    // six adapters against a stubbed transport and additionally asserts *which*
    // reason each condition produces. Duplicating the weaker assertions here
    // would only give two places to update.
    //
    // The one guarantee that had no counterpart there, that a changed key
    // cannot inherit the previous key's figures, moved with it.

    func testUnsupportedProvidersNeverInventQuota() async throws {
        let unsupported: [AIProviderAdapter] = [CursorAdapter(), WindsurfAdapter(homeDirectory: root.path),
                                                ZedAdapter(homeDirectory: root.path), MistralAdapter(homeDirectory: root.path)]
        for adapter in unsupported {
            let snapshot = try await adapter.fetchUsage(forceSync: true)
            XCTAssertTrue(snapshot.isSimulated, "\(adapter.type)")
            XCTAssertTrue(snapshot.modelQuotas.isEmpty)
            XCTAssertNil(snapshot.hourlyResetCountdown)
        }
    }

    private func rollout(day: String, measured: Date, used: Int, started: Date? = nil) throws -> URL {
        let dir = root.appendingPathComponent("sessions/\(day)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        var events: [[String: Any]] = []
        if let started { events.append(["type": "session_meta", "timestamp": formatter.string(from: started)]) }
        events.append(["timestamp": formatter.string(from: measured), "payload": ["type": "token_count",
                      "rate_limits": ["primary": ["used_percent": used]]]])
        let lines = try events.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        let url = dir.appendingPathComponent("rollout-fixture.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: measured], ofItemAtPath: url.path)
        return url
    }

    func testResumedOlderDirectoryWinsOverNewerDirectoryAndLegacyFile() throws {
        let now = Date()
        _ = try rollout(day: "2026/09/05", measured: now, used: 90)
        _ = try rollout(day: "2026/09/06", measured: now.addingTimeInterval(-600), used: 10)
        _ = try rollout(day: "", measured: now.addingTimeInterval(-900), used: 5)
        XCTAssertEqual(OpenAI_CodexAdapter.rateLimits(codexHome: root.path)?.primary?.remaining, 10)
    }

    func testMeasurementTimestampWinsOverUnrelatedFileModification() throws {
        let now = Date()
        _ = try rollout(day: "2026/09/05", measured: now, used: 90)
        let older = try rollout(day: "2026/09/06", measured: now.addingTimeInterval(-600), used: 10)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(600)], ofItemAtPath: older.path)
        XCTAssertEqual(OpenAI_CodexAdapter.rateLimits(codexHome: root.path)?.primary?.remaining, 10)
    }

    private func auth(account: String, modified: Date) throws -> CodexAccountResolver.Profile {
        let claims: [String: Any] = ["email": "\(account)@example.com", "https://api.openai.com/auth": ["chatgpt_account_id": account]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        let data = try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": "header.\(payload).signature"]])
        let url = root.appendingPathComponent("auth.json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return .init(authPath: url.path, homeDirectory: root.path, isDefault: true)
    }

    func testLoginSwitchAndRestartRejectPreviousAccountSessions() throws {
        let now = Date(timeIntervalSince1970: 1788696000)
        let profile = try auth(account: "A", modified: now.addingTimeInterval(-1000))
        _ = try rollout(day: "2026/09/06", measured: now.addingTimeInterval(-100), used: 80,
                        started: now.addingTimeInterval(-900))
        let first = OpenAI_CodexAdapter().snapshot(for: profile)
        XCTAssertEqual(first.accountID, "A")
        XCTAssertEqual(first.hourlyRemainingPercentage, 20)
        _ = try auth(account: "B", modified: now)
        let switched = OpenAI_CodexAdapter().snapshot(for: profile)
        XCTAssertEqual(switched.accountID, "B")
        XCTAssertTrue(switched.isSimulated)
        // A still-running old session writing after login B must not be relabelled.
        _ = try rollout(day: "2026/09/06", measured: now.addingTimeInterval(10), used: 90,
                        started: now.addingTimeInterval(-900))
        XCTAssertTrue(OpenAI_CodexAdapter().snapshot(for: profile).isSimulated)
        _ = try rollout(day: "2026/09/07", measured: now.addingTimeInterval(100), used: 30,
                        started: now.addingTimeInterval(60))
        let fresh = OpenAI_CodexAdapter().snapshot(for: profile)
        XCTAssertEqual(fresh.accountID, "B")
        XCTAssertEqual(fresh.hourlyRemainingPercentage, 70)
        XCTAssertFalse(fresh.isSimulated)
    }

    func testMissingSessionProvenanceAndAPIKeyModeAreUnknown() throws {
        let now = Date()
        let profile = try auth(account: "A", modified: now.addingTimeInterval(-1000))
        _ = try rollout(day: "2026/09/06", measured: now, used: 50)
        XCTAssertTrue(OpenAI_CodexAdapter().snapshot(for: profile).isSimulated)
        try Data("{\"OPENAI_API_KEY\":\"fixture\"}".utf8).write(to: URL(fileURLWithPath: profile.authPath))
        let unknown = OpenAI_CodexAdapter().snapshot(for: profile)
        XCTAssertTrue(unknown.isSimulated)
        XCTAssertNil(unknown.accountID)
    }
}
