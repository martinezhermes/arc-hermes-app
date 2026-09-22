import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AppIconChoice: String, CaseIterable, Identifiable {
    case system
    case wingedHelmet
    case pixelCaduceus
    case pixelCaduceusDark
    case nousResearch
    case nousResearchDark
    case nousResearchChromeLight
    case nousResearchChromeDark
    case nousResearchGlassLight
    case nousResearchGlassDark

    // Keep the existing alternate names so retained selections survive updates.
    static let wingedHelmetAlternateIconName = "AppIconWingedHelmet"
    static let pixelCaduceusAlternateIconName = "AppIconPixelCaduceus"
    static let pixelCaduceusDarkAlternateIconName = "AppIconPixelCaduceusDark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .wingedHelmet: String(localized: "ARC Helmet")
        case .pixelCaduceus: String(localized: "Pixel Caduceus")
        case .pixelCaduceusDark: String(localized: "Pixel Caduceus Dark")
        case .nousResearch: String(localized: "Nous Research")
        case .nousResearchDark: String(localized: "Nous Research Dark")
        case .nousResearchChromeLight: String(localized: "Nous Research Chrome Light")
        case .nousResearchChromeDark: String(localized: "Nous Research Chrome Dark")
        case .nousResearchGlassLight: String(localized: "Nous Research Glass Light")
        case .nousResearchGlassDark: String(localized: "Nous Research Glass Dark")
        }
    }

    var subtitle: String {
        switch self {
        case .system, .wingedHelmet:
            String(localized: "Matches device appearance")
        case .pixelCaduceus:
            String(localized: "Original artwork")
        case .nousResearch, .nousResearchChromeLight, .nousResearchGlassLight:
            String(localized: "Always use the light icon")
        case .pixelCaduceusDark, .nousResearchDark, .nousResearchChromeDark, .nousResearchGlassDark:
            String(localized: "Always use the dark icon")
        }
    }

    var alternateIconName: String? {
        switch self {
        case .system: nil
        case .wingedHelmet: Self.wingedHelmetAlternateIconName
        case .pixelCaduceus: Self.pixelCaduceusAlternateIconName
        case .pixelCaduceusDark: Self.pixelCaduceusDarkAlternateIconName
        case .nousResearch: "AppIconNousResearch"
        case .nousResearchDark: "AppIconNousResearchDark"
        case .nousResearchChromeLight: "AppIconNousResearchChromeLight"
        case .nousResearchChromeDark: "AppIconNousResearchChromeDark"
        case .nousResearchGlassLight: "AppIconNousResearchGlassLight"
        case .nousResearchGlassDark: "AppIconNousResearchGlassDark"
        }
    }

    var previewImageName: String? {
        alternateIconName.map { "\($0)Preview" }
    }

    static func resolved(from alternateIconName: String?) -> AppIconChoice {
        allCases.first { $0.alternateIconName == alternateIconName } ?? .system
    }

    /// Compare the actual OS selection so a retired alternate can reset to System.
    func matches(alternateIconName: String?) -> Bool {
        self.alternateIconName == alternateIconName
    }

    #if canImport(UIKit)
    @MainActor
    static var current: AppIconChoice {
        resolved(from: UIApplication.shared.alternateIconName)
    }
    #endif
}
