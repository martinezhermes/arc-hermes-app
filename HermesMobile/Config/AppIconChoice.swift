import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AppIconChoice: String, CaseIterable, Identifiable {
    case system
    case classicCaduceus
    case wingedHelmet
    case arcMonogram
    case pixelCaduceus
    case light
    case dark
    case disco
    case monochromeLight
    case monochromeDark
    case gradientLight
    case gradientDark

    static let lightAlternateIconName = "AppIconLight"
    static let classicCaduceusAlternateIconName = "AppIconClassicCaduceus"
    static let wingedHelmetAlternateIconName = "AppIconWingedHelmet"
    static let arcMonogramAlternateIconName = "AppIconARCMonogram"
    static let pixelCaduceusAlternateIconName = "AppIconPixelCaduceus"
    static let darkAlternateIconName = "AppIconDark"
    static let discoAlternateIconName = "AppIconDisco"
    static let monochromeLightAlternateIconName = "AppIconMonochromeLight"
    static let monochromeDarkAlternateIconName = "AppIconMonochromeDark"
    static let gradientLightAlternateIconName = "AppIconGradientLight"
    static let gradientDarkAlternateIconName = "AppIconGradientDark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            String(localized: "System")
        case .classicCaduceus:
            String(localized: "Classic Caduceus")
        case .wingedHelmet:
            String(localized: "Winged Helmet")
        case .arcMonogram:
            String(localized: "ARC Monogram")
        case .pixelCaduceus:
            String(localized: "Pixel Caduceus")
        case .light:
            String(localized: "Light")
        case .dark:
            String(localized: "Dark")
        case .disco:
            String(localized: "Disco")
        case .monochromeLight:
            String(localized: "Monochrome Light")
        case .monochromeDark:
            String(localized: "Monochrome Dark")
        case .gradientLight:
            String(localized: "Gradient Light")
        case .gradientDark:
            String(localized: "Gradient Dark")
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            String(localized: "Matches device appearance")
        case .classicCaduceus, .wingedHelmet, .arcMonogram, .pixelCaduceus:
            String(localized: "Original artwork")
        case .light:
            String(localized: "Always use the light icon")
        case .dark:
            String(localized: "Always use the dark icon")
        case .disco:
            String(localized: "Always use the disco icon")
        case .monochromeLight:
            String(localized: "Always use the monochrome light icon")
        case .monochromeDark:
            String(localized: "Always use the monochrome dark icon")
        case .gradientLight:
            String(localized: "Always use the gradient light icon")
        case .gradientDark:
            String(localized: "Always use the gradient dark icon")
        }
    }

    var alternateIconName: String? {
        switch self {
        case .system:
            nil
        case .classicCaduceus:
            Self.classicCaduceusAlternateIconName
        case .wingedHelmet:
            Self.wingedHelmetAlternateIconName
        case .arcMonogram:
            Self.arcMonogramAlternateIconName
        case .pixelCaduceus:
            Self.pixelCaduceusAlternateIconName
        case .light:
            Self.lightAlternateIconName
        case .dark:
            Self.darkAlternateIconName
        case .disco:
            Self.discoAlternateIconName
        case .monochromeLight:
            Self.monochromeLightAlternateIconName
        case .monochromeDark:
            Self.monochromeDarkAlternateIconName
        case .gradientLight:
            Self.gradientLightAlternateIconName
        case .gradientDark:
            Self.gradientDarkAlternateIconName
        }
    }

    var previewImageName: String? {
        switch self {
        case .system:
            nil
        case .classicCaduceus:
            "AppIconClassicCaduceusPreview"
        case .wingedHelmet:
            "AppIconWingedHelmetPreview"
        case .arcMonogram:
            "AppIconARCMonogramPreview"
        case .pixelCaduceus:
            "AppIconPixelCaduceusPreview"
        case .light:
            "AppIconLightPreview"
        case .dark:
            "AppIconDarkPreview"
        case .disco:
            "AppIconDiscoPreview"
        case .monochromeLight:
            "AppIconMonochromeLightPreview"
        case .monochromeDark:
            "AppIconMonochromeDarkPreview"
        case .gradientLight:
            "AppIconGradientLightPreview"
        case .gradientDark:
            "AppIconGradientDarkPreview"
        }
    }

    static func resolved(from alternateIconName: String?) -> AppIconChoice {
        switch alternateIconName {
        case Self.classicCaduceusAlternateIconName:
            .classicCaduceus
        case Self.wingedHelmetAlternateIconName:
            .wingedHelmet
        case Self.arcMonogramAlternateIconName:
            .arcMonogram
        case Self.pixelCaduceusAlternateIconName:
            .pixelCaduceus
        case Self.lightAlternateIconName:
            .light
        case Self.darkAlternateIconName:
            .dark
        case Self.discoAlternateIconName:
            .disco
        case Self.monochromeLightAlternateIconName:
            .monochromeLight
        case Self.monochromeDarkAlternateIconName:
            .monochromeDark
        case Self.gradientLightAlternateIconName:
            .gradientLight
        case Self.gradientDarkAlternateIconName:
            .gradientDark
        default:
            .system
        }
    }

    #if canImport(UIKit)
    @MainActor
    static var current: AppIconChoice {
        resolved(from: UIApplication.shared.alternateIconName)
    }
    #endif
}
