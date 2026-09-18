import XCTest
@testable import Glancie

/// A stand-in for the one HTTP call an adapter makes.
///
/// Everything an adapter has to survive — a rejected key, a rate-limit refusal,
/// a timeout, a body that decodes to nothing useful — is a scripted answer here,
/// so none of it needs a live account or a network.
struct StubTransport: UsageTransport {
    enum Answer {
        case status(Int, body: String)
        case failure(URLError.Code)
        case nonHTTPResponse
    }

    let answer: Answer
    let url = URL(string: "https://example.invalid/usage")!

    static func ok(_ body: String) -> StubTransport { StubTransport(answer: .status(200, body: body)) }
    static func status(_ code: Int) -> StubTransport { StubTransport(answer: .status(code, body: "{}")) }
    static func failing(_ code: URLError.Code) -> StubTransport { StubTransport(answer: .failure(code)) }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch answer {
        case .status(let code, let body):
            let response = HTTPURLResponse(
                url: request.url ?? url,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        case .nonHTTPResponse:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }
}

/// An API error must never leave the adapter looking like a measurement.
final class UsageFailureStateTests: XCTestCase {

    // MARK: - Helpers

    private func homeWithKey(_ relativePath: String) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-failure-\(UUID().uuidString)")
        let keyPath = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: keyPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("sk-test-key".utf8).write(to: keyPath)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.path
    }

    private func assertUnavailable(
        _ snapshot: UsageSnapshot,
        _ expected: UsageUnavailableReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.unavailableReason, expected, file: file, line: line)
        XCTAssertTrue(snapshot.isSimulated, "a failed read is not a measurement", file: file, line: line)
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0.0, file: file, line: line)
        XCTAssertNil(snapshot.weeklyRemainingPercentage, file: file, line: line)
        XCTAssertTrue(snapshot.modelQuotas.isEmpty, "no invented amounts", file: file, line: line)
    }

    /// Every adapter that talks to an HTTP API, as one table.
    private typealias AdapterFactory = (String, UsageTransport) -> AIProviderAdapter
    private static let adapters: [(name: String, make: AdapterFactory)] = [
        ("deepseek", { DeepSeekAdapter(homeDirectory: $0, transport: $1) }),
        ("kimi", { KimiAdapter(homeDirectory: $0, transport: $1) }),
        ("openrouter", { OpenRouterAdapter(homeDirectory: $0, transport: $1) }),
        ("groq", { GroqAdapter(homeDirectory: $0, transport: $1) }),
        ("elevenlabs", { ElevenLabsAdapter(homeDirectory: $0, transport: $1) }),
        ("copilot", { CopilotAdapter(homeDirectory: $0, transport: $1) })
    ]

    private func keyPath(for adapter: String) -> String {
        switch adapter {
        case "deepseek": return ".config/deepseek/api_key"
        case "kimi": return ".config/moonshot/api_key"
        case "openrouter": return ".config/openrouter/api_key"
        case "groq": return ".config/groq/api_key"
        case "elevenlabs": return ".config/elevenlabs/api_key"
        default: return ".config/github-copilot/hosts.json"
        }
    }

    /// Copilot's credential lives inside a JSON document rather than a bare file.
    private func home(for adapter: String) throws -> String {
        guard adapter == "copilot" else { return try homeWithKey(keyPath(for: adapter)) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-failure-\(UUID().uuidString)")
        let hosts = root.appendingPathComponent(".config/github-copilot/hosts.json")
        try FileManager.default.createDirectory(
            at: hosts.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"github.com": {"oauth_token": "gho_test"}}"#.utf8).write(to: hosts)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.path
    }

    // MARK: - The status-code matrix

    func testEveryAdapterPreservesTheHTTPFailureStatus() async throws {
        let expectations: [(Int, UsageUnavailableReason)] = [
            (401, .authenticationFailed),
            (403, .authenticationFailed),
            (429, .rateLimited),
            (500, .providerError),
            (503, .providerError)
        ]

        for (name, make) in Self.adapters {
            let home = try home(for: name)
            for (status, reason) in expectations {
                let snapshot = try await make(home, StubTransport.status(status))
                    .fetchUsage(forceSync: true)
                XCTAssertEqual(
                    snapshot.unavailableReason, reason,
                    "\(name) should report \(reason) for HTTP \(status)"
                )
                assertUnavailable(snapshot, reason)
            }
        }
    }

    func testEveryAdapterPreservesTransportFailures() async throws {
        for (name, make) in Self.adapters {
            let home = try home(for: name)
            for code in [URLError.timedOut, .notConnectedToInternet, .cannotFindHost] {
                let snapshot = try await make(home, StubTransport.failing(code))
                    .fetchUsage(forceSync: true)
                XCTAssertEqual(
                    snapshot.unavailableReason, .networkFailure,
                    "\(name) should report a network failure for \(code)"
                )
                assertUnavailable(snapshot, .networkFailure)
            }
        }
    }

    func testEveryAdapterRejectsAMalformedBody() async throws {
        for (name, make) in Self.adapters {
            let home = try home(for: name)
            for body in ["", "not json at all", "{}", #"{"data": {}}"#] {
                let snapshot = try await make(home, StubTransport.ok(body))
                    .fetchUsage(forceSync: true)
                XCTAssertEqual(
                    snapshot.unavailableReason, .malformedResponse,
                    "\(name) should reject the body \(body.isEmpty ? "<empty>" : body)"
                )
                assertUnavailable(snapshot, .malformedResponse)
            }
        }
    }

    func testAFailedReadIsNotStampedWithACurrentMeasurementTime() async throws {
        // The old fallbacks defaulted `capturedAt` to now under a real strategy
        // badge, so a failure aged like a fresh reading and never went stale.
        let home = try home(for: "deepseek")
        let snapshot = try await DeepSeekAdapter(homeDirectory: home, transport: StubTransport.status(401))
            .fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.strategyUsed, FetchStrategy.simulated)
        XCTAssertNotEqual(snapshot.strategyUsed, FetchStrategy.oauthKeychain, "no false provenance")
    }

    // MARK: - Detection is not a measurement

    func testDetectedButEmptyDeepSeekConfigIsUnknown() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.isEmpty ?? true,
            "a real key in the environment would resolve"
        )
        // Verbatim from the audit: an empty key file made `isDetected` true, no
        // request was sent, and the adapter reported 100%.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-failure-\(UUID().uuidString)")
        let keyFile = root.appendingPathComponent(".config/deepseek/api_key")
        try FileManager.default.createDirectory(
            at: keyFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: keyFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let adapter = DeepSeekAdapter(homeDirectory: root.path, transport: StubTransport.ok("{}"))
        let snapshot = try await adapter.fetchUsage(forceSync: true)

        XCTAssertTrue(adapter.isDetected, "the file exists, so detection still fires")
        assertUnavailable(snapshot, .notConfigured)
    }

    // MARK: - The success paths still work

    func testDeepSeekReadsARealBalance() async throws {
        let home = try home(for: "deepseek")
        let body = #"{"is_available": true, "balance_infos": [{"currency": "USD", "total_balance": "10.00", "granted_balance": "4.00", "topped_up_balance": "6.00"}]}"#
        let snapshot = try await DeepSeekAdapter(homeDirectory: home, transport: StubTransport.ok(body))
            .fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.strategyUsed, FetchStrategy.oauthKeychain)
        XCTAssertFalse(snapshot.modelQuotas.isEmpty)
    }

    func testGroqWithoutRateLimitHeadersIsUnknownRatherThanFull() async throws {
        // A 200 from `/models` proves the key works and reports no budget. The
        // old code defaulted both percentages to 100%.
        let home = try home(for: "groq")
        let snapshot = try await GroqAdapter(homeDirectory: home, transport: StubTransport.ok("{}"))
            .fetchUsage(forceSync: true)

        assertUnavailable(snapshot, .malformedResponse)
    }

    func testCopilotQuotaSnapshotsWithoutAKnownPoolIsUnknown() async throws {
        let home = try home(for: "copilot")
        let snapshot = try await CopilotAdapter(
            homeDirectory: home,
            transport: StubTransport.ok(#"{"quota_snapshots": {"something_else": {"used": 1}}}"#)
        ).fetchUsage(forceSync: true)

        assertUnavailable(snapshot, .malformedResponse)
    }

    func testCopilotReadsARealQuota() async throws {
        let home = try home(for: "copilot")
        let body = #"{"quota_snapshots": {"premium_interactions": {"credits_used": 25, "credits_total": 100}, "chat": {"used": 10, "limit": 50}}}"#
        let snapshot = try await CopilotAdapter(homeDirectory: home, transport: StubTransport.ok(body))
            .fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 75.0)
        XCTAssertEqual(snapshot.weeklyRemainingPercentage, 80.0)
    }

    func testANonHTTPResponseIsMalformedRatherThanASuccess() async throws {
        let home = try home(for: "kimi")
        let snapshot = try await KimiAdapter(
            homeDirectory: home,
            transport: StubTransport(answer: .nonHTTPResponse)
        ).fetchUsage(forceSync: true)

        assertUnavailable(snapshot, .malformedResponse)
    }

    // MARK: - Reason classification

    func testStatusCodesMapToTheReasonTheyMean() {
        XCTAssertEqual(UsageUnavailableReason(httpStatus: 401), .authenticationFailed)
        XCTAssertEqual(UsageUnavailableReason(httpStatus: 403), .authenticationFailed)
        XCTAssertEqual(UsageUnavailableReason(httpStatus: 429), .rateLimited)
        XCTAssertEqual(UsageUnavailableReason(httpStatus: 500), .providerError)
        XCTAssertEqual(UsageUnavailableReason(httpStatus: 418), .providerError)
    }

    func testATimeoutIsANetworkFailureNotAProviderError() {
        // The provider never answered, so nothing has been established about it.
        XCTAssertEqual(UsageUnavailableReason(transportError: URLError(.timedOut)), .networkFailure)
        XCTAssertEqual(UsageUnavailableReason(transportError: URLError(.cancelled)), .networkFailure)
    }

    func testOnlyRecoverableConditionsCountAsTransient() {
        for reason in [UsageUnavailableReason.authenticationFailed, .rateLimited, .networkFailure, .malformedResponse, .providerError] {
            XCTAssertTrue(reason.isTransient, "\(reason) may clear on its own")
        }
        for reason in [UsageUnavailableReason.notConfigured, .notMeasured] {
            XCTAssertFalse(reason.isTransient, "\(reason) describes the account, not the request")
        }
    }

    func testEveryReasonHasADistinctLabel() {
        let all: [UsageUnavailableReason] = [
            .notConfigured, .notMeasured, .authenticationFailed,
            .rateLimited, .networkFailure, .malformedResponse, .providerError
        ]
        XCTAssertEqual(Set(all.map(\.displayText)).count, all.count)
    }

    func testAFailureReasonSurvivesACodableRoundTrip() throws {
        for reason in [UsageUnavailableReason.rateLimited, .authenticationFailed, .networkFailure] {
            let original = UsageSnapshot.unavailable(for: .groq, reason: reason)
            let decoded = try JSONDecoder().decode(
                UsageSnapshot.self,
                from: JSONEncoder().encode(original)
            )
            XCTAssertEqual(decoded.unavailableReason, reason)
        }
    }

    // MARK: - The store

    func testAFailedReadIsNeverPersisted() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-store-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = AccountUsageStore(fileURL: file)

        var failed = UsageSnapshot.unavailable(for: .groq, reason: .rateLimited)
        failed.accountID = "acct-1"
        store.record(failed)

        XCTAssertNil(
            store.snapshot(provider: .groq, accountID: "acct-1"),
            "a rate-limit refusal must not resurface later as a dated reading"
        )
    }
}

/// What a failed refresh does to the reading already on screen.
@MainActor
final class TransientFailureRetentionTests: XCTestCase {

    private func measurement(_ percentage: Double, capturedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: .groq,
            hourlyRemainingPercentage: percentage,
            strategyUsed: .oauthKeychain,
            capturedAt: capturedAt
        )
    }

    func testARateLimitDoesNotWipeTheLastReading() {
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        let refused = UsageSnapshot.unavailable(for: .groq, reason: .rateLimited)

        let shown = ProviderManager.preferringLastMeasurement(refused, over: last)

        XCTAssertEqual(shown.hourlyRemainingPercentage, 42)
        XCTAssertEqual(
            shown.capturedAt, last.capturedAt,
            "the reading keeps its own measurement time, so it ages honestly"
        )
    }

    func testEveryTransientFailureKeepsTheLastReading() {
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        for reason in [UsageUnavailableReason.authenticationFailed, .rateLimited, .networkFailure, .malformedResponse, .providerError] {
            let shown = ProviderManager.preferringLastMeasurement(
                .unavailable(for: .groq, reason: reason),
                over: last
            )
            XCTAssertEqual(shown.hourlyRemainingPercentage, 42, "\(reason) should not blank the bar")
        }
    }

    func testSigningOutReplacesTheReading() {
        // Not transient: the account itself changed, so the old figures stop
        // describing anything and must go.
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        for reason in [UsageUnavailableReason.notConfigured, .notMeasured] {
            let shown = ProviderManager.preferringLastMeasurement(
                .unavailable(for: .groq, reason: reason),
                over: last
            )
            XCTAssertTrue(shown.isSimulated, "\(reason) must clear the figures")
        }
    }

    func testWithoutAPriorReadingTheFailureIsWhatIsShown() {
        let shown = ProviderManager.preferringLastMeasurement(
            .unavailable(for: .groq, reason: .networkFailure),
            over: nil
        )
        XCTAssertEqual(shown.unavailableReason, .networkFailure)
        XCTAssertEqual(shown.hourlyRemainingPercentage, 0)
    }

    func testAFailureNeverOverridesASuccessfulRefresh() {
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        let fresh = measurement(11, capturedAt: Date(timeIntervalSince1970: 2000))

        XCTAssertEqual(
            ProviderManager.preferringLastMeasurement(fresh, over: last).hourlyRemainingPercentage,
            11,
            "a real reading always wins"
        )
    }

    func testARefusedKeyKeepsTheReadingOnlyWhileItIsTheSameKey() {
        // A 401 is transient — a key can be refused and work again a minute
        // later — so the reading survives it. But once the credential on disk
        // has changed, those figures belong to the account the old key named,
        // and showing them under the new one attributes a stranger's balance.
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        var keyA = last
        keyA.credentialFingerprint = UsageSnapshot.fingerprint("account-A")

        var refusedSameKey = UsageSnapshot.unavailable(for: .groq, reason: .authenticationFailed)
        refusedSameKey.credentialFingerprint = UsageSnapshot.fingerprint("account-A")
        XCTAssertEqual(
            ProviderManager.preferringLastMeasurement(refusedSameKey, over: keyA).hourlyRemainingPercentage,
            42,
            "the same key being refused says nothing new about the quota"
        )

        var refusedNewKey = UsageSnapshot.unavailable(for: .groq, reason: .authenticationFailed)
        refusedNewKey.credentialFingerprint = UsageSnapshot.fingerprint("account-B")
        let shown = ProviderManager.preferringLastMeasurement(refusedNewKey, over: keyA)
        XCTAssertTrue(shown.isSimulated, "B must not inherit A's figures")
        XCTAssertEqual(shown.unavailableReason, .authenticationFailed)
    }

    func testAnUnknownCredentialIsNotTreatedAsAMismatch() {
        // CLI and local-file providers never fill the fingerprint in; that
        // absence must not be read as "the key changed".
        let last = measurement(42, capturedAt: Date(timeIntervalSince1970: 1000))
        var refused = UsageSnapshot.unavailable(for: .groq, reason: .rateLimited)
        refused.credentialFingerprint = UsageSnapshot.fingerprint("account-A")

        XCTAssertEqual(
            ProviderManager.preferringLastMeasurement(refused, over: last).hourlyRemainingPercentage,
            42
        )
        var keyed = last
        keyed.credentialFingerprint = UsageSnapshot.fingerprint("account-A")
        XCTAssertEqual(
            ProviderManager.preferringLastMeasurement(
                .unavailable(for: .groq, reason: .rateLimited), over: keyed
            ).hourlyRemainingPercentage,
            42
        )
    }

    func testAFingerprintNamesTheKeyWithoutCarryingIt() {
        XCTAssertEqual(UsageSnapshot.fingerprint("sk-secret"), UsageSnapshot.fingerprint("sk-secret"))
        XCTAssertNotEqual(UsageSnapshot.fingerprint("sk-secret"), UsageSnapshot.fingerprint("sk-other"))
        XCTAssertFalse(
            UsageSnapshot.fingerprint("sk-secret").contains("sk-secret"),
            "the key itself must never reach the snapshot store"
        )
    }

    func testAStalePlaceholderIsNotMistakenForAMeasurement() {
        // Two failures in a row must not let the first one's blank become the
        // "last reading" the second one preserves.
        let firstFailure = UsageSnapshot.unavailable(for: .groq, reason: .networkFailure)
        let secondFailure = UsageSnapshot.unavailable(for: .groq, reason: .rateLimited)

        let shown = ProviderManager.preferringLastMeasurement(secondFailure, over: firstFailure)

        XCTAssertEqual(shown.unavailableReason, .rateLimited, "the newest reason wins")
    }
}
