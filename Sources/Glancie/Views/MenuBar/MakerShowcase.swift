import SwiftUI

/// The maker's other work, as shown on the About screen.
///
/// Hard-coded rather than fetched: the About screen must open instantly and
/// offline, and Glancie has no server of its own — reaching out to a site on
/// every open would be the first network call the app makes that is not a
/// provider's usage API. The cost is that this list ages by hand when the lab
/// changes, which is the trade the "no server" rule asks for everywhere else
/// too.
public struct MakerProduct: Identifiable {
    public enum Category {
        case iOS
        case web
        case crypto

        var label: String {
            switch self {
            case .iOS: return "iOS"
            case .web: return "Web"
            case .crypto: return "Crypto"
            }
        }

        /// Tints drawn from the same family the provider tiles use, so a product
        /// row reads as part of this app rather than an advert dropped into it.
        var colors: [Color] {
            switch self {
            case .iOS: return [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)]
            case .web: return [Color(hex: 0x30D158), Color(hex: 0x18863A)]
            case .crypto: return [Color(hex: 0xBF5AF2), Color(hex: 0x7A2CB0)]
            }
        }

        var symbol: String {
            switch self {
            case .iOS: return "iphone"
            case .web: return "globe"
            case .crypto: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    public let id: String
    public let name: String
    public let summary: String
    public let category: Category
    public let url: URL
    /// Shown with its own badge. The lab marks one product as an experiment, and
    /// saying so is the difference between a showcase and a claim.
    public let isExperimental: Bool
}

/// Who made Glancie, and what else they have shipped.
public enum MakerShowcase {
    public static let siteURL = URL(string: "https://www.storyqbe.com")!
    public static let sourceURL = URL(string: "https://github.com/ktkfree/glancie")!

    public static var products: [MakerProduct] {
        [
            MakerProduct(
                id: "ivent",
                name: L10n.productIVent.text,
                summary: L10n.productIVentSummary.text,
                category: .iOS,
                url: URL(string: "https://ivent.storyqbe.com")!,
                isExperimental: false
            ),
            MakerProduct(
                id: "aptmap",
                name: L10n.productAptMap.text,
                summary: L10n.productAptMapSummary.text,
                category: .web,
                url: URL(string: "https://aptmap.storyqbe.com/about")!,
                isExperimental: false
            ),
            MakerProduct(
                id: "qbetools",
                name: L10n.productQbeTools.text,
                summary: L10n.productQbeToolsSummary.text,
                category: .web,
                url: URL(string: "https://qbetools.storyqbe.com")!,
                isExperimental: false
            ),
            MakerProduct(
                id: "unbubble",
                name: L10n.productUnbubble.text,
                summary: L10n.productUnbubbleSummary.text,
                category: .web,
                url: URL(string: "https://unbubble-dev.storyqbe.top")!,
                isExperimental: true
            ),
            MakerProduct(
                id: "quantpersona",
                name: L10n.productQuantPersona.text,
                summary: L10n.productQuantPersonaSummary.text,
                category: .crypto,
                url: URL(string: "https://quant-persona.storyqbe.com")!,
                isExperimental: false
            )
        ]
    }

    public static var liveCount: Int {
        products.filter { !$0.isExperimental }.count
    }
}
