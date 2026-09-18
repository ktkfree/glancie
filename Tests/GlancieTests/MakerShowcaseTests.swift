import XCTest
@testable import Glancie

final class MakerShowcaseTests: XCTestCase {
    private var original: ResolvedLanguage = .korean

    override func setUp() {
        super.setUp()
        original = Localization.current
    }

    override func tearDown() {
        Localization.renderLanguage(original)
        super.tearDown()
    }

    /// Every row in the About screen is a link the user will click. A typo in one
    /// is invisible until someone lands on a dead page, so check the shape of all
    /// of them here rather than by hand.
    func testEveryProductLinkIsAnHTTPSAddress() {
        for product in MakerShowcase.products {
            XCTAssertEqual(product.url.scheme, "https", "\(product.id) must not be plain http")
            XCTAssertNotNil(product.url.host, "\(product.id) has no host")
        }
        XCTAssertEqual(MakerShowcase.siteURL.scheme, "https")
        XCTAssertEqual(MakerShowcase.sourceURL.scheme, "https")
    }

    func testProductIdentifiersAreUnique() {
        let ids = MakerShowcase.products.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a duplicate id would collapse two rows in the ForEach")
    }

    /// The card claims a count beside the word "운영중". It has to be derived from
    /// the list rather than typed, or it goes stale the moment a product is added.
    func testTheLiveCountMatchesTheProductsThatAreNotExperiments() {
        let experiments = MakerShowcase.products.filter(\.isExperimental).count
        XCTAssertEqual(MakerShowcase.liveCount, MakerShowcase.products.count - experiments)
        XCTAssertGreaterThan(MakerShowcase.liveCount, 0)
    }

    func testEveryProductIsNamedAndDescribedInBothLanguages() {
        for language in [ResolvedLanguage.korean, .english] {
            Localization.renderLanguage(language)
            for product in MakerShowcase.products {
                XCTAssertFalse(product.name.isEmpty, "\(product.id) has no name in \(language.rawValue)")
                XCTAssertFalse(product.summary.isEmpty, "\(product.id) has no summary in \(language.rawValue)")
            }
        }
    }

    /// The screen is built from this list, so an empty one would ship an empty
    /// section rather than a missing one.
    func testTheShowcaseIsNotEmpty() {
        XCTAssertGreaterThanOrEqual(MakerShowcase.products.count, 1)
    }
}
