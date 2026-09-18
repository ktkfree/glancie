import XCTest
@testable import Glancie

private final class MutableUsageResolver: AccountResolver {
    let provider: AIProviderType = .openAICodex
    let primarySourceID = "codex.cli"
    let identities = Locked<[AccountIdentity]>([])
    func resolveAccounts() async -> [AccountIdentity] { identities.value }
}

private final class MutableUsageAdapter: AIProviderAdapter {
    let type: AIProviderType = .openAICodex
    let isDetected = true
    let result = Locked<Result<[UsageSnapshot], Error>>(.success([]))
    func checkAvailability() async -> Bool { true }
    func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot { try result.value.get()[0] }
    func fetchUsagePerAccount(forceSync: Bool) async throws -> [UsageSnapshot] { try result.value.get() }
}

@MainActor
final class UsageAccountTransitionTests: XCTestCase {
    private func identity(_ id: String) -> AccountIdentity {
        .init(id: id, provider: .openAICodex,
              source: .init(id: "codex.cli", kind: .cli, displayName: "CLI"),
              email: "\(id)@example.com", usageReadable: true)
    }
    private func snapshot(_ id: String, remaining: Double, at: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(provider: .openAICodex, hourlyRemainingPercentage: remaining,
                      lastUpdated: at, accountID: id)
    }
    private func store() -> AccountUsageStore {
        AccountUsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testRefreshDiscoversSwitchedAccountBeforeApplyingUsage() async {
        let resolver = MutableUsageResolver()
        resolver.identities.value = [identity("A")]
        let registry = AccountRegistry(resolvers: [resolver])
        await registry.refreshAccounts()
        let adapter = MutableUsageAdapter()
        let history = store()
        let manager = ProviderManager(adapters: [adapter], accountRegistry: registry, usageStore: history)
        adapter.result.value = .success([snapshot("A", remaining: 20)])
        await manager.refreshProvider(.openAICodex, forceSync: true)
        resolver.identities.value = [identity("B")]
        adapter.result.value = .success([snapshot("B", remaining: 70)])
        await manager.refreshProvider(.openAICodex, forceSync: true)
        XCTAssertEqual(manager.snapshots[.openAICodex]?.accountID, "B")
        XCTAssertEqual(manager.snapshots[.openAICodex]?.accountEmail, "B@example.com")
        XCTAssertEqual(manager.snapshots[.openAICodex]?.hourlyRemainingPercentage, 70)
        XCTAssertNil(manager.accountSnapshots[.openAICodex]?["A"])
        XCTAssertEqual(history.snapshot(provider: .openAICodex, accountID: "A")?.hourlyRemainingPercentage, 20)
    }

    func testDuplicateProfilesPickNewestMeasurementInEitherOrder() async {
        let resolver = MutableUsageResolver()
        resolver.identities.value = [identity("A")]
        let registry = AccountRegistry(resolvers: [resolver])
        await registry.refreshAccounts()
        let manager = ProviderManager(adapters: [], accountRegistry: registry, usageStore: store())
        let latest = snapshot("A", remaining: 20)
        let old = snapshot("A", remaining: 80, at: latest.capturedAt.addingTimeInterval(-60))
        for readings in [[latest, old], [old, latest]] {
            manager.apply(readings, for: .openAICodex)
            XCTAssertEqual(manager.snapshots[.openAICodex]?.hourlyRemainingPercentage, 20)
        }
        var unavailable = UsageSnapshot.simulatedFallback(for: .openAICodex)
        unavailable.accountID = "A"
        manager.apply([latest, unavailable], for: .openAICodex)
        XCTAssertEqual(manager.snapshots[.openAICodex]?.hourlyRemainingPercentage, 20)
    }

    func testLogoutClearsLiveQuotaAndUnknownIdentityIsNotGuessed() async {
        let resolver = MutableUsageResolver()
        resolver.identities.value = [identity("A")]
        let registry = AccountRegistry(resolvers: [resolver])
        await registry.refreshAccounts()
        let adapter = MutableUsageAdapter()
        let manager = ProviderManager(adapters: [adapter], accountRegistry: registry, usageStore: store())
        manager.apply([snapshot("A", remaining: 20)], for: .openAICodex)
        manager.apply([UsageSnapshot.simulatedFallback(for: .openAICodex)], for: .openAICodex)
        XCTAssertNil(manager.snapshots[.openAICodex]?.accountID)
        XCTAssertNil(manager.snapshots[.openAICodex]?.accountEmail)
        resolver.identities.value = []
        adapter.result.value = .success([])
        await manager.refreshProvider(.openAICodex, forceSync: true)
        XCTAssertTrue(manager.accountSnapshots[.openAICodex]?.isEmpty == true)
        XCTAssertTrue(manager.snapshots[.openAICodex]?.isSimulated == true)
    }

    func testFailurePreservesOnlyCurrentAccountsDatedReading() async {
        let resolver = MutableUsageResolver()
        resolver.identities.value = [identity("A")]
        let registry = AccountRegistry(resolvers: [resolver])
        let adapter = MutableUsageAdapter()
        let history = store()
        let manager = ProviderManager(adapters: [adapter], accountRegistry: registry, usageStore: history)
        let first = snapshot("A", remaining: 20)
        adapter.result.value = .success([first])
        await manager.refreshProvider(.openAICodex, forceSync: true)
        adapter.result.value = .failure(UsageFetchError.httpStatus(401))
        await manager.refreshProvider(.openAICodex, forceSync: true)
        XCTAssertEqual(manager.snapshots[.openAICodex]?.capturedAt, first.capturedAt)
        XCTAssertTrue(manager.snapshots[.openAICodex]?.isStale == true)
        XCTAssertNil(history.snapshot(provider: .openAICodex, accountID: "A")?.fetchError)
        resolver.identities.value = [identity("B")]
        await manager.refreshProvider(.openAICodex, forceSync: true)
        XCTAssertEqual(manager.snapshots[.openAICodex]?.accountID, "B")
        XCTAssertTrue(manager.snapshots[.openAICodex]?.isSimulated == true)
    }
}
