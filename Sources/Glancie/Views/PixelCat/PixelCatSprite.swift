import SwiftUI

/// Supported Cat Breeds / Coat Styles
///
/// The raw values are Korean because that is what shipped, and they are what is
/// written to `UserDefaults`. Renaming them would silently reset every existing
/// user's chosen coat to the default, so they stay as storage keys and
/// `displayName` is what the UI reads.
public enum PixelCatBreed: String, CaseIterable, Identifiable, Codable {
    case orangeTabby = "치즈 태비"
    case calico = "삼색이"
    case tuxedo = "턱시도"
    case snowWhite = "터키시 앙고라"
    case blackCat = "검은 고양이"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .orangeTabby: return L10n.catOrangeTabby.text
        case .calico: return L10n.catCalico.text
        case .tuxedo: return L10n.catTuxedo.text
        case .snowWhite: return L10n.catTurkishAngora.text
        case .blackCat: return L10n.catBlack.text
        }
    }

    public var palette: CatColorPalette {
        switch self {
        case .orangeTabby:
            return CatColorPalette(
                body: Color(red: 0.98, green: 0.62, blue: 0.22),
                dark: Color(red: 0.82, green: 0.42, blue: 0.12),
                white: Color(red: 0.98, green: 0.96, blue: 0.92),
                pink: Color(red: 1.0, green: 0.72, blue: 0.78),
                eye: Color(red: 0.18, green: 0.62, blue: 0.35) // Emerald green
            )
        case .calico:
            return CatColorPalette(
                body: Color(red: 0.96, green: 0.94, blue: 0.90),
                dark: Color(red: 0.88, green: 0.48, blue: 0.18),
                white: Color(red: 0.22, green: 0.22, blue: 0.25),
                pink: Color(red: 1.0, green: 0.70, blue: 0.75),
                eye: Color(red: 0.95, green: 0.75, blue: 0.18) // Amber
            )
        case .tuxedo:
            return CatColorPalette(
                body: Color(red: 0.18, green: 0.18, blue: 0.22),
                dark: Color(red: 0.10, green: 0.10, blue: 0.12),
                white: Color(red: 0.98, green: 0.98, blue: 0.98),
                pink: Color(red: 1.0, green: 0.72, blue: 0.78),
                eye: Color(red: 0.96, green: 0.82, blue: 0.22) // Yellow
            )
        case .snowWhite:
            return CatColorPalette(
                body: Color(red: 0.98, green: 0.98, blue: 0.99),
                dark: Color(red: 0.86, green: 0.88, blue: 0.92),
                white: Color(red: 1.0, green: 1.0, blue: 1.0),
                pink: Color(red: 1.0, green: 0.75, blue: 0.82),
                eye: Color(red: 0.32, green: 0.68, blue: 0.95) // Sky blue
            )
        case .blackCat:
            return CatColorPalette(
                body: Color(red: 0.14, green: 0.14, blue: 0.16),
                dark: Color(red: 0.08, green: 0.08, blue: 0.10),
                white: Color(red: 0.26, green: 0.26, blue: 0.30),
                pink: Color(red: 0.85, green: 0.55, blue: 0.60),
                eye: Color(red: 0.98, green: 0.88, blue: 0.25) // Bright Gold
            )
        }
    }
}

public struct CatColorPalette {
    public let body: Color
    public let dark: Color
    public let white: Color
    public let pink: Color
    public let eye: Color
}

/// 16x16 Pixel Art Matrix representation for ultra-crisp Retina rendering
public struct PixelCatFrame {
    public let rows: [String]
    
    public init(_ rows: [String]) {
        self.rows = rows
    }
}

/// All Sprite Animations for the Pixel Cat
public enum PixelCatSprites {
    // MARK: - Walk Cycle (16x16)
    public static let walk1 = PixelCatFrame([
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEB........",
        ".BEWBEEW...BBB..",
        ".BWWPWWBBBBBD...",
        "..BBBBBBBBBBB...",
        "...BBBBBBBBBB...",
        "..WW.BBBB.WW....",
        ".WW........WW...",
        "................",
        "................",
        "................",
        "................"
    ])
    
    public static let walk2 = PixelCatFrame([
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEB........",
        ".BEWBEEW..BBB...",
        ".BWWPWWBBBBBD...",
        "..BBBBBBBBBBB...",
        "...BBBBBBBBBB...",
        "...WW.BBBB.WW...",
        "....WW....WW....",
        "................",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Idle (Standing & Tail Wag)
    public static let idle1 = PixelCatFrame([
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEB........",
        ".BEWBEEW..BB....",
        ".BWWPWWBBBBDB...",
        "..BBBBBBBBBBDB..",
        "...BBBBBBBBBB...",
        "...WWBBBBWWBB...",
        "...WW....WW.....",
        "................",
        "................",
        "................",
        "................"
    ])
    
    public static let idle2 = PixelCatFrame([
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEB...BB...",
        ".BEWBEEW..BDB...",
        ".BWWPWWBBBBDB...",
        "..BBBBBBBBBB....",
        "...BBBBBBBBBB...",
        "...WWBBBBWWBB...",
        "...WW....WW.....",
        "................",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Sitting (Eyes Open & Blink)
    public static let sit1 = PixelCatFrame([
        "................",
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEB........",
        ".BEWBEEW........",
        ".BWWPWWBBBB.....",
        "..BBBBBBBBBD....",
        "..BBBBBBBBBDB...",
        "..BBBBBBBBBD....",
        "..WW.WW.BBBB....",
        "................",
        "................",
        "................"
    ])
    
    public static let sit2 = PixelCatFrame([
        "................",
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B........",
        ".B--B--B........",
        ".BWWPWWBBBB.....",
        "..BBBBBBBBBD....",
        "..BBBBBBBBBDB...",
        "..BBBBBBBBBD....",
        "..WW.WW.BBBB....",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Grooming / Wash Paw
    public static let wash1 = PixelCatFrame([
        "................",
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B........",
        ".BWWPWWWP.......",
        "..BBBBBBWW......",
        "..BBBBBBBBBD....",
        "..BBBBBBBBBDB...",
        "..BBBBBBBBBD....",
        "..WW.WW.BBBB....",
        "................",
        "................",
        "................"
    ])
    
    public static let wash2 = PixelCatFrame([
        "................",
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B........",
        ".BWWPWWWP.......",
        "...BBBBBBBWW....",
        "..BBBBBBBBBD....",
        "..BBBBBBBBBDB...",
        "..BBBBBBBBBD....",
        "..WW.WW.BBBB....",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Bread Loaf / Laying Down
    public static let loaf = PixelCatFrame([
        "................",
        "................",
        "................",
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".BEEBEEBBBBBBB..",
        ".BEWBEEWBBBBBDD.",
        ".BWWPWWBBBBBBDB.",
        "..BBBBBBBBBBBBB.",
        "..WWWWWWWWWWWW..",
        "................",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Sleeping zZ
    public static let sleep1 = PixelCatFrame([
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "...D...D........",
        "..BP.PBBBBBBBB..",
        ".BBBBBBBBBBBBDD.",
        ".B--B--BBBBBBBDB",
        ".BWWPWWBBBBBBBBB",
        ".WWWWWWWWWWWWWW.",
        "................",
        "................",
        "................"
    ])
    
    public static let sleep2 = PixelCatFrame([
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "...D...D........",
        "..BP.PBBBBBBBB..",
        ".BBBBBBBBBBBBDD.",
        ".B--B--BBBBBBBDB",
        ".BWWPWWBBBBBBBBB",
        "..WWWWWWWWWWWW..",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Stretch
    public static let stretch = PixelCatFrame([
        "................",
        "................",
        "................",
        "................",
        "........D...D...",
        "........BP.PB...",
        ".......BBBBBBB..",
        "......BEEBEEB...",
        ".....BEWBEEW....",
        "....BBWWPWWBB...",
        "..BBBBBBBBBBBB..",
        ".WWWW...BBBBWW..",
        "................",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Happy / Jump
    public static let happy = PixelCatFrame([
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB...B....",
        ".B--B--B..BDB...",
        ".BWWPWWBBBBDB...",
        "..BBBBBBBBBB....",
        "...BBBBBBBB.....",
        "..WW....WW......",
        ".WW......WW.....",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................"
    ])
    
    // MARK: - Dangling / Struggling (Held by cursor)
    public static let dangle1 = PixelCatFrame([
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B........",
        ".BWWPWWBB.......",
        "..BBBBBBBB......",
        "..WW.BB.WW......",
        "...WW..WW.......",
        "...BBBBBB.......",
        "...BBBBBB.......",
        "..WW.BB.WW......",
        ".WW..BB...WW....",
        ".....BB.........",
        "......B.........",
        "................"
    ])
    
    public static let dangle2 = PixelCatFrame([
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B...B....",
        ".BWWPWWBB.BDB...",
        "..BBBBBBBBB.....",
        ".WW..BB..WW.....",
        "..WW.BB.WW......",
        "...BBBBBB.......",
        "...BBBBBB.......",
        "....BB.BB.......",
        "...WW...WW......",
        "..WW.....WW.....",
        "................",
        "................"
    ])
    
    public static let dangle3 = PixelCatFrame([
        "................",
        "..D...D.........",
        "..BP.PB.........",
        ".BBBBBBB........",
        ".B--B--B........",
        ".BWWPWWBB.......",
        "..BBBBBBBB..B...",
        "...WW..WW..BDB..",
        "..WW....WW.BB...",
        "...BBBBBB.......",
        "...BBBBBB.......",
        "..WW.BB.WW......",
        "...WW..WW.......",
        "....BB..........",
        ".....B..........",
        "................"
    ])
}

/// SwiftUI Canvas-based Pixel Art Renderer
public struct PixelArtCanvas: View {
    public let frameData: PixelCatFrame
    public let palette: CatColorPalette
    public let pixelSize: CGFloat
    
    public init(frameData: PixelCatFrame, palette: CatColorPalette, pixelSize: CGFloat = 1.35) {
        self.frameData = frameData
        self.palette = palette
        self.pixelSize = pixelSize
    }
    
    public var body: some View {
        Canvas { context, size in
            let rows = frameData.rows
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = colorForChar(char) else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(frameData.rows.first?.count ?? 16) * pixelSize,
            height: CGFloat(frameData.rows.count) * pixelSize
        )
    }
    
    private func colorForChar(_ char: Character) -> Color? {
        switch char {
        case "B": return palette.body
        case "D": return palette.dark
        case "W": return palette.white
        case "P": return palette.pink
        case "E": return palette.eye
        case "-": return Color(red: 0.15, green: 0.15, blue: 0.18) // Closed eye line
        default: return nil // Transparent
        }
    }
}
