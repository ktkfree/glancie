import XCTest
@testable import Glancie

final class GlancieTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }

    
    func testCharacterStateMapping() {
        XCTAssertEqual(CharacterState.from(percentage: 95.0), .energetic)
        XCTAssertEqual(CharacterState.from(percentage: 80.0), .energetic)
        XCTAssertEqual(CharacterState.from(percentage: 79.9), .focused)
        XCTAssertEqual(CharacterState.from(percentage: 30.0), .focused)
        XCTAssertEqual(CharacterState.from(percentage: 29.9), .tired)
        XCTAssertEqual(CharacterState.from(percentage: 10.0), .tired)
        XCTAssertEqual(CharacterState.from(percentage: 9.9), .sleeping)
        XCTAssertEqual(CharacterState.from(percentage: 0.0), .sleeping)
    }
    
    func testUsageSnapshotClamping() {
        let snapshotOver = UsageSnapshot(provider: .claudeCode, hourlyRemainingPercentage: 150.0)
        XCTAssertEqual(snapshotOver.hourlyRemainingPercentage, 100.0)
        
        let snapshotUnder = UsageSnapshot(provider: .openAICodex, hourlyRemainingPercentage: -20.0)
        XCTAssertEqual(snapshotUnder.hourlyRemainingPercentage, 0.0)
    }
    
    func testUsageColorTheme() {
        let fullColors = UsageColorTheme.gradientColors(for: 100.0)
        XCTAssertEqual(fullColors.count, 2)
        
        let emptyColors = UsageColorTheme.gradientColors(for: 0.0)
        XCTAssertEqual(emptyColors.count, 2)
        
        let midColors = UsageColorTheme.gradientColors(for: 50.0)
        XCTAssertEqual(midColors.count, 2)
        
        let snapshotFull = UsageSnapshot(provider: .antigravity, hourlyRemainingPercentage: 100.0)
        XCTAssertEqual(snapshotFull.gradientColors.count, 2)
    }
    
    func testProviderManagerToggle() async {
        let manager = await ProviderManager(adapters: [], accountRegistry: AccountRegistry(resolvers: []),
                                            usageStore: AccountUsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        
        let targetProvider: AIProviderType = .elevenlabs
        let containsTarget = await manager.activeProviders.contains(targetProvider)
        
        if containsTarget {
            await manager.toggleProvider(targetProvider)
            let afterRemove = await manager.activeProviders.contains(targetProvider)
            XCTAssertFalse(afterRemove)
            
            await manager.toggleProvider(targetProvider)
            let afterReAdd = await manager.activeProviders.contains(targetProvider)
            XCTAssertTrue(afterReAdd)
        } else {
            let initialCount = await manager.activeProviders.count
            await manager.toggleProvider(targetProvider)
            let countAfterAdd = await manager.activeProviders.count
            XCTAssertEqual(countAfterAdd, initialCount + 1)
            
            await manager.toggleProvider(targetProvider)
            let countAfterRemove = await manager.activeProviders.count
            XCTAssertEqual(countAfterRemove, initialCount)
        }
    }
    
    func testRealLocalAdaptersFetching() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GLANCIE_RUN_LOCAL_INTEGRATION_TESTS"] == "1",
            "Requires configured local providers; enable with GLANCIE_RUN_LOCAL_INTEGRATION_TESTS=1"
        )
        let claudeAdapter = ClaudeCodeAdapter()
        let isClaudeDetected = await claudeAdapter.checkAvailability()
        let claudeSnapshot = try await claudeAdapter.fetchUsage()
        XCTAssertTrue(isClaudeDetected)
        XCTAssertGreaterThanOrEqual(claudeSnapshot.hourlyRemainingPercentage, 0.0)
        XCTAssertLessThanOrEqual(claudeSnapshot.hourlyRemainingPercentage, 100.0)
        XCTAssertFalse(claudeSnapshot.modelQuotas.isEmpty)
        
        let agyAdapter = AntigravityAdapter()
        let isAgyDetected = await agyAdapter.checkAvailability()
        let agySnapshot = try await agyAdapter.fetchUsage()
        XCTAssertTrue(isAgyDetected)
        XCTAssertGreaterThanOrEqual(agySnapshot.hourlyRemainingPercentage, 0.0)
        XCTAssertLessThanOrEqual(agySnapshot.hourlyRemainingPercentage, 100.0)
        XCTAssertFalse(agySnapshot.modelQuotas.isEmpty)
        
        let copilotAdapter = CopilotAdapter()
        let copilotSnapshot = try await copilotAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(copilotSnapshot.hourlyRemainingPercentage, 0.0)
        
        let deepseekAdapter = DeepSeekAdapter()
        let deepseekSnapshot = try await deepseekAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(deepseekSnapshot.hourlyRemainingPercentage, 0.0)
        
        let openrouterAdapter = OpenRouterAdapter()
        let openrouterSnapshot = try await openrouterAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(openrouterSnapshot.hourlyRemainingPercentage, 0.0)
        
        let groqAdapter = GroqAdapter()
        let groqSnapshot = try await groqAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(groqSnapshot.hourlyRemainingPercentage, 0.0)
        
        let ollamaAdapter = OllamaAdapter()
        let ollamaSnapshot = try await ollamaAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(ollamaSnapshot.hourlyRemainingPercentage, 0.0)
        
        let kimiAdapter = KimiAdapter()
        let kimiSnapshot = try await kimiAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(kimiSnapshot.hourlyRemainingPercentage, 0.0)
        
        let mistralAdapter = MistralAdapter()
        let mistralSnapshot = try await mistralAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(mistralSnapshot.hourlyRemainingPercentage, 0.0)
        
        let elevenlabsAdapter = ElevenLabsAdapter()
        let elevenlabsSnapshot = try await elevenlabsAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(elevenlabsSnapshot.hourlyRemainingPercentage, 0.0)
        
        let windsurfAdapter = WindsurfAdapter()
        let windsurfSnapshot = try await windsurfAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(windsurfSnapshot.hourlyRemainingPercentage, 0.0)
        
        let zedAdapter = ZedAdapter()
        let zedSnapshot = try await zedAdapter.fetchUsage()
        XCTAssertGreaterThanOrEqual(zedSnapshot.hourlyRemainingPercentage, 0.0)
    }
    
    func testActivityFilterEngineRules() throws {
        let registry = AIActivityRuleRegistry()
        let engine = AIActivityFilterEngine(registry: registry)
        
        // 1. Global blacklist extension (.lock, .tmp) should be ignored
        let lockEval = engine.evaluateEvent(eventPath: "/Users/test/.claude/session.lock", provider: .claudeCode)
        XCTAssertTrue(lockEval.isIgnored)
        
        // 2. Global blacklist subpath (/cache/, .session.lock)
        let cacheEval = engine.evaluateEvent(eventPath: "/Users/test/.gemini/antigravity-cli/cache/file.json", provider: .antigravity)
        XCTAssertTrue(cacheEval.isIgnored)
        
        // 3. Test content blacklist: Claude local /usage command output
        let tempDir = FileManager.default.temporaryDirectory
        let usageLogFile = tempDir.appendingPathComponent("messages_usage_test.json")
        let usageContent = """
        {"parentUuid":"f11e8356","type":"system","subtype":"local_command","content":"<command-name>/usage</command-name><local-command-stdout>Current session: 0% used</local-command-stdout>","isMeta":true}
        """
        try usageContent.write(to: usageLogFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: usageLogFile) }
        
        let usageEval = engine.evaluateEvent(eventPath: usageLogFile.path, provider: .claudeCode)
        XCTAssertTrue(usageEval.isIgnored, "Local /usage log must be ignored")
        
        // 4. Test content whitelist: Real Claude Assistant message streaming
        let assistantLogFile = tempDir.appendingPathComponent("messages_assistant_test.json")
        let assistantContent = """
        {"type":"user","message":{"role":"assistant","content":"Sure, here is the implementation..."}}
        """
        try assistantContent.write(to: assistantLogFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: assistantLogFile) }
        
        let assistantEval = engine.evaluateEvent(eventPath: assistantLogFile.path, provider: .claudeCode)
        XCTAssertTrue(assistantEval.isImmediateStreaming, "Real assistant generation must be detected as immediate streaming")
    }
    
    func testRegistryDynamicRuleModification() {
        let registry = AIActivityRuleRegistry()
        
        // Add a new custom blacklist keyword
        registry.addContentBlacklistKeyword("custom_ping", for: .cursor)
        let rule = registry.rule(for: .cursor)
        XCTAssertTrue(rule?.contentBlacklistKeywords.contains("custom_ping") == true)
        
        // Add a new provider rule
        registry.registerRule(ProviderFilterRule(
            provider: .deepseek,
            relativeRootPaths: [".deepseek"],
            pathWhitelist: ["chat"],
            contentWhitelistKeywords: ["assistant"]
        ))
        XCTAssertNotNil(registry.rule(for: .deepseek))
        
        // Remove rule
        registry.removeRule(for: .deepseek)
        XCTAssertNil(registry.rule(for: .deepseek))
    }
    
    @MainActor
    func testMenuBarNavigator() {
        let navigator = MenuBarNavigator()
        XCTAssertEqual(navigator.screen, .overview)
        XCTAssertTrue(navigator.isForward)
        
        navigator.push(.providerDetail(.claudeCode))
        XCTAssertEqual(navigator.screen, .providerDetail(.claudeCode))
        XCTAssertTrue(navigator.isForward)
        
        navigator.push(.settings)
        XCTAssertEqual(navigator.screen, .settings)
        XCTAssertTrue(navigator.isForward)
        
        navigator.popToRoot()
        XCTAssertEqual(navigator.screen, .overview)
        XCTAssertFalse(navigator.isForward)
        
        navigator.push(.settings)
        XCTAssertEqual(navigator.screen, .settings)
        
        navigator.reset()
        XCTAssertEqual(navigator.screen, .overview)
        XCTAssertTrue(navigator.isForward)
    }
    
    func testFormattingHelpers() {
        let now = Date()
        XCTAssertEqual(relativeUpdateText(now), "방금 업데이트")
        
        let thirtySecondsAgo = now.addingTimeInterval(-30)
        XCTAssertEqual(relativeUpdateText(thirtySecondsAgo), "방금 업데이트")
        
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        XCTAssertEqual(relativeUpdateText(fiveMinutesAgo), "5분 전 업데이트")
        
        let twoHoursAgo = now.addingTimeInterval(-7200)
        XCTAssertEqual(relativeUpdateText(twoHoursAgo), "2시간 전 업데이트")
        
        XCTAssertEqual(quotaCountdownText(30), "곧 리셋")
        XCTAssertEqual(quotaCountdownText(300), "5분 후")
        XCTAssertEqual(quotaCountdownText(7200), "2시간 후")
        XCTAssertEqual(quotaCountdownText(9000), "2시간 30분 후")
    }
    
    func testSurfaceAndUsageTier() {
        XCTAssertEqual(UsageTier.abundant.label, "여유")
        XCTAssertEqual(UsageTier.abundant.symbol, "bolt.fill")
        
        XCTAssertEqual(UsageTier.steady.label, "안정")
        XCTAssertEqual(UsageTier.steady.symbol, "checkmark.circle.fill")
        
        XCTAssertEqual(UsageTier.caution.label, "주의")
        XCTAssertEqual(UsageTier.caution.symbol, "exclamationmark.triangle.fill")
        
        XCTAssertEqual(UsageTier.critical.label, "임박")
        XCTAssertEqual(UsageTier.critical.symbol, "hourglass")
        
        XCTAssertEqual(UsageTier.from(100), .abundant)
        XCTAssertEqual(UsageTier.from(75), .abundant)
        XCTAssertEqual(UsageTier.from(74.9), .steady)
        XCTAssertEqual(UsageTier.from(45), .steady)
        XCTAssertEqual(UsageTier.from(44.9), .caution)
        XCTAssertEqual(UsageTier.from(20), .caution)
        XCTAssertEqual(UsageTier.from(19.9), .critical)
        XCTAssertEqual(UsageTier.from(0), .critical)
    }
}
