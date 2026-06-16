import XCTest
@testable import TokenPet

final class TokenPetTests: XCTestCase {
    
    @MainActor
    func testSettingsDefaults() {
        let settings = SettingsManager.shared
        XCTAssert(settings.petSize >= 0.5 && settings.petSize <= 2.0)
        XCTAssertEqual(settings.alwaysOnTop, true)
        XCTAssertEqual(settings.showNotifications, true)
        XCTAssertFalse(settings.geminiKeywords.isEmpty)
        XCTAssertFalse(settings.codexKeywords.isEmpty)
    }
    
    @MainActor
    func testQuotaCalculations() {
        let settings = SettingsManager.shared
        let quota = QuotaManager.shared
        
        let originalThreshold5h = settings.quota5hThreshold
        settings.quota5hThreshold = 10
        
        // Mock usage data
        CCDataCoordinator.shared.usageData = CCUsageData(
            rateLimits: CodexRateLimits(
                primary5hUsedPercent: 71.0,
                primary5hResetsAt: Date().addingTimeInterval(3600),
                secondary7dUsedPercent: 99.0,
                secondary7dResetsAt: Date().addingTimeInterval(86400),
                planType: "plus",
                sessionTimestamp: Date()
            ),
            tokenSummary: TokenUsageSummary(
                inputTokens5h: 1000, outputTokens5h: 100, cachedInputTokens5h: 500,
                inputTokens7d: 10000, outputTokens7d: 1000, cachedInputTokens7d: 5000,
                sessionCount5h: 1, sessionCount7d: 3
            ),
            geminiCalls5h: 5,
            geminiCalls7d: 15,
            lastUpdated: Date(),
            dataSource: "Test Data"
        )
        
        // Wait for Combine sync
        let expectation = self.expectation(description: "Combine sync")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 0.2)
        
        XCTAssertEqual(quota.quota5hUsed, 71)
        XCTAssertEqual(quota.quota5hRemaining, 29)
        XCTAssertEqual(quota.quota5hPercent, 0.29)
        XCTAssertEqual(quota.is5hWarning, false) // 29 > 10, so warning is false
        
        settings.quota5hThreshold = originalThreshold5h
    }
}
