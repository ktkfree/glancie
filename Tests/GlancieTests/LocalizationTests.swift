import XCTest
@testable import Glancie

final class LocalizationTests: XCTestCase {
    private var original: ResolvedLanguage = .korean

    override func setUp() {
        super.setUp()
        original = Localization.current
    }

    override func tearDown() {
        Localization.renderLanguage(original)
        super.tearDown()
    }

    // MARK: - Resolving `system`

    func testAKoreanSystemGetsKorean() {
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["ko-KR", "en-US"]), .korean)
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["ko"]), .korean)
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["ko-Kore-KR"]), .korean)
    }

    func testEverySystemOtherThanKoreanGetsEnglish() {
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["de-DE", "ko-KR"]), .english)
    }

    /// Only the first entry decides. A Korean user who lists English second still
    /// wants Korean, and an English user who keeps Korean as a fallback must not
    /// be flipped into it.
    func testOnlyTheTopPreferenceIsConsulted() {
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["ko-KR", "en-US"]), .korean)
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["en-US", "ko-KR"]), .english)
    }

    func testAMacThatNamesNoLanguageGetsEnglish() {
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: []), .english)
    }

    /// `kok` is Konkani, not Korean. Matching on a prefix rather than the whole
    /// subtag would hand it the Korean strings.
    func testANeighbouringLanguageTagIsNotMistakenForKorean() {
        XCTAssertEqual(Localization.resolve(.system, preferredLanguages: ["kok-IN"]), .english)
    }

    func testAnExplicitChoiceOverridesTheSystem() {
        XCTAssertEqual(Localization.resolve(.korean, preferredLanguages: ["en-US"]), .korean)
        XCTAssertEqual(Localization.resolve(.english, preferredLanguages: ["ko-KR"]), .english)
    }

    // MARK: - Rendering

    func testTheSameKeyRendersInWhicheverLanguageIsCurrent() {
        Localization.renderLanguage(.korean)
        XCTAssertEqual(L10n.refreshAll.text, "모두 새로 고침")

        Localization.renderLanguage(.english)
        XCTAssertEqual(L10n.refreshAll.text, "Refresh All")
    }

    func testInterpolatedArgumentsSurviveBothLanguages() {
        Localization.renderLanguage(.korean)
        XCTAssertEqual(L10n.codexWindowHours(5).text, "5시간 한도")

        Localization.renderLanguage(.english)
        XCTAssertEqual(L10n.codexWindowHours(5).text, "5-hour limit")
    }

    /// Under a minute the countdown is already a complete phrase, so the reset
    /// line must not append the word a second time.
    func testTheResetLineDoesNotRepeatItselfInsideTheLastMinute() {
        Localization.renderLanguage(.korean)
        XCTAssertEqual(L10n.resetLine(30).text, "곧 리셋")
        XCTAssertEqual(L10n.resetLine(7200).text, "2시간 후 리셋")

        Localization.renderLanguage(.english)
        XCTAssertEqual(L10n.resetLine(30).text, "Resets soon")
        XCTAssertEqual(L10n.resetLine(7200).text, "Resets in 2h")
    }

    /// Quota names are built by the adapters, so they have to follow the language
    /// too — otherwise the bar reads half-translated.
    func testAdapterProducedQuotaNamesFollowTheLanguage() {
        Localization.renderLanguage(.english)
        XCTAssertEqual(UsageUnavailableReason.notConfigured.displayText, "Not connected")
        XCTAssertEqual(UsageTier.critical.label, "Critical")

        Localization.renderLanguage(.korean)
        XCTAssertEqual(UsageUnavailableReason.notConfigured.displayText, "연결 대기 중")
        XCTAssertEqual(UsageTier.critical.label, "임박")
    }

    // MARK: - Persistence

    /// The choice has to outlive a launch, and it is read before any view
    /// exists — a preference that only took effect on the second run would look
    /// like the switch did nothing.
    func testAStoredChoiceIsReadBackOnTheNextLaunch() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "LocalizationTests.persistence"))
        defer { suite.removeSuite(named: "LocalizationTests.persistence") }
        suite.removePersistentDomain(forName: "LocalizationTests.persistence")

        let first = Localization(defaults: suite)
        XCTAssertEqual(first.preference, .system, "an untouched install follows the system")

        first.setPreference(.english)
        XCTAssertEqual(suite.string(forKey: Localization.storageKey), "english")

        let relaunched = Localization(defaults: suite)
        XCTAssertEqual(relaunched.preference, .english)
    }

    func testAnUnreadableStoredValueFallsBackToTheSystem() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "LocalizationTests.garbage"))
        defer { suite.removeSuite(named: "LocalizationTests.garbage") }
        suite.removePersistentDomain(forName: "LocalizationTests.garbage")
        suite.set("esperanto", forKey: Localization.storageKey)

        XCTAssertEqual(Localization(defaults: suite).preference, .system)
    }

    // MARK: - Catalogue

    /// Reads `L10n.swift` itself rather than enumerating cases, which an enum
    /// with associated values cannot be made to do. The failure this guards is
    /// the realistic one: a case added with the Korean text pasted into both
    /// sides, or an empty placeholder left behind. The compiler already refuses
    /// a case that is missing a language outright.
    func testEveryEnglishStringIsActuallyEnglish() throws {
        let source = try catalogueSource()
        let pairs = try translationPairs(in: source)

        XCTAssertGreaterThan(
            pairs.count, 180,
            "the catalogue is parsed, not silently skipped — if this drops, the scan stopped matching"
        )

        for (line, korean, english) in pairs {
            XCTAssertFalse(korean.isEmpty, "empty Korean string on line \(line)")
            XCTAssertFalse(english.isEmpty, "empty English string on line \(line)")
            XCTAssertFalse(
                english.contains(where: isHangul),
                "untranslated English string on line \(line): \(english)"
            )
        }
    }

    // MARK: - Helpers

    private func catalogueSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GlancieTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/Glancie/Localization/L10n.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)     // syllables
                || (0x1100...0x11FF).contains(scalar.value)  // jamo
                || (0x3130...0x318F).contains(scalar.value)  // compatibility jamo
        }
    }

    /// Pulls the `("…", "…")` tuples out of the catalogue.
    ///
    /// The long entries are wrapped across lines, so both shapes are read: the
    /// one-liner, and `return (` followed by a string on each of the next two
    /// lines. Missing the wrapped form would leave exactly the longest — and
    /// most likely to be left untranslated — strings unchecked.
    private func translationPairs(in source: String) throws -> [(line: Int, ko: String, en: String)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var pairs: [(Int, String, String)] = []

        for (index, line) in lines.enumerated() {
            if line == "return (" {
                guard index + 2 < lines.count,
                      let ko = unquote(lines[index + 1].hasSuffix(",")
                                       ? String(lines[index + 1].dropLast())
                                       : lines[index + 1]),
                      let en = unquote(lines[index + 2].hasSuffix(",")
                                       ? String(lines[index + 2].dropLast())
                                       : lines[index + 2])
                else { continue }
                pairs.append((index + 2, ko, en))
                continue
            }

            guard line.hasPrefix("return ("), line.hasSuffix(")") else { continue }
            let inner = String(line.dropFirst("return (".count).dropLast())
            guard let split = topLevelComma(in: inner) else { continue }
            let ko = unquote(String(inner[inner.startIndex..<split]))
            let en = unquote(String(inner[inner.index(after: split)...]))
            guard let ko, let en else { continue }
            pairs.append((index + 1, ko, en))
        }
        return pairs
    }

    /// The comma separating the two strings, skipping any inside a literal.
    private func topLevelComma(in text: String) -> String.Index? {
        var insideString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                insideString.toggle()
            } else if character == ",", !insideString {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func unquote(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }
}
