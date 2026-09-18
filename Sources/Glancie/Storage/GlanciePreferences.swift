import SwiftUI

/// Persistent Settings & User Preferences
public final class GlanciePreferences: ObservableObject {
    public static let shared = GlanciePreferences()
    
    @AppStorage("panelOriginX") public var panelOriginX: Double = -1.0
    @AppStorage("panelOriginY") public var panelOriginY: Double = -1.0
    /// The size the bar actually had when it was last on screen.
    ///
    /// Stored alongside the position because the window has to exist before
    /// SwiftUI can measure anything: without it the panel is born at a guessed
    /// width and the first real layout shoves it sideways. Negative means "not
    /// recorded yet" — preferences written by earlier versions have a position
    /// but no size.
    @AppStorage("panelWidth") public var panelWidth: Double = -1.0
    @AppStorage("panelHeight") public var panelHeight: Double = -1.0
    @AppStorage("soundEnabled") public var soundEnabled: Bool = true {
        didSet {
            SoundEffectsEngine.shared.isSoundEnabled = soundEnabled
        }
    }
    @AppStorage("eyeTrackingEnabled") public var eyeTrackingEnabled: Bool = true
    @AppStorage("refreshIntervalSeconds") public var refreshIntervalSeconds: Double = 60.0
    @AppStorage("pixelCatEnabled") public var pixelCatEnabled: Bool = true
    @AppStorage("pixelCatBreedRaw") private var pixelCatBreedRaw: String = PixelCatBreed.orangeTabby.rawValue
    /// Show `i***@gmail.com` rather than the full address. On by default: the bar
    /// sits over whatever the user is screen-sharing.
    @AppStorage("maskAccountEmails") public var maskAccountEmails: Bool = true
    /// Whether to look for provider logins at all. Turning it off leaves the
    /// quota meters working, without reading any provider's account files.
    @AppStorage("accountScanEnabled") public var accountScanEnabled: Bool = true
    @AppStorage("hasCustomizedProviders") public var hasCustomizedProviders: Bool = false
    @AppStorage("enabledProvidersJSON") private var enabledProvidersJSON: String = ""

    public var enabledProviders: [AIProviderType]? {
        get {
            guard hasCustomizedProviders, !enabledProvidersJSON.isEmpty,
                  let data = enabledProvidersJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([AIProviderType].self, from: data) else {
                return nil
            }
            return list
        }
        set {
            if let newValue = newValue {
                hasCustomizedProviders = true
                if let data = try? JSONEncoder().encode(newValue),
                   let str = String(data: data, encoding: .utf8) {
                    enabledProvidersJSON = str
                }
            } else {
                hasCustomizedProviders = false
                enabledProvidersJSON = ""
            }
            objectWillChange.send()
        }
    }

    public var pixelCatBreed: PixelCatBreed {
        get {
            PixelCatBreed(rawValue: pixelCatBreedRaw) ?? .orangeTabby
        }
        set {
            pixelCatBreedRaw = newValue.rawValue
            objectWillChange.send()
        }
    }
    
    private init() {
        SoundEffectsEngine.shared.isSoundEnabled = soundEnabled
    }
}
