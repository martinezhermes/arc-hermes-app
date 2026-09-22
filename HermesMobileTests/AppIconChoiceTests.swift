import XCTest
import UIKit
@testable import HermesMobile

final class AppIconChoiceTests: XCTestCase {
    func testApprovedChoicesAndOrder() {
        XCTAssertEqual(AppIconChoice.allCases, [
            .system, .wingedHelmet, .pixelCaduceus, .pixelCaduceusDark,
            .nousResearch, .nousResearchDark, .nousResearchChromeLight,
            .nousResearchChromeDark, .nousResearchGlassLight, .nousResearchGlassDark
        ])
    }

    func testRetainedAlternateNamesSurviveTheRename() {
        XCTAssertNil(AppIconChoice.system.alternateIconName)
        XCTAssertEqual(AppIconChoice.resolved(from: "AppIconWingedHelmet"), .wingedHelmet)
        XCTAssertEqual(AppIconChoice.wingedHelmet.title, "ARC Helmet")
        XCTAssertEqual(AppIconChoice.resolved(from: "AppIconPixelCaduceus"), .pixelCaduceus)
        XCTAssertEqual(AppIconChoice.resolved(from: "AppIconPixelCaduceusDark"), .pixelCaduceusDark)
    }

    func testRetiredSelectionCanStillResetToSystem() {
        for name in ["AppIconLight", "AppIconDark", "AppIconDisco", "AppIconClassicCaduceus",
                     "AppIconARCMonogram", "AppIconARCMonogramDark", "AppIconMonochromeLight",
                     "AppIconMonochromeDark", "AppIconGradientLight", "AppIconGradientDark", "UnknownIcon"] {
            XCTAssertEqual(AppIconChoice.resolved(from: name), .system)
            XCTAssertFalse(AppIconChoice.system.matches(alternateIconName: name),
                           "A fallback label must not prevent resetting a retired OS selection")
        }
        XCTAssertTrue(AppIconChoice.system.matches(alternateIconName: nil))
    }

    func testNousDisplayMetadata() {
        XCTAssertEqual(AppIconChoice.nousResearch.title, "Nous Research")
        XCTAssertEqual(AppIconChoice.nousResearchDark.title, "Nous Research Dark")
        XCTAssertEqual(AppIconChoice.nousResearchChromeLight.title, "Nous Research Chrome Light")
        XCTAssertEqual(AppIconChoice.nousResearchChromeDark.title, "Nous Research Chrome Dark")
        XCTAssertEqual(AppIconChoice.nousResearchGlassLight.title, "Nous Research Glass Light")
        XCTAssertEqual(AppIconChoice.nousResearchGlassDark.title, "Nous Research Glass Dark")
        XCTAssertEqual(AppIconChoice.system.subtitle, "Matches device appearance")
        XCTAssertEqual(AppIconChoice.wingedHelmet.subtitle, "Matches device appearance")
    }

    func testSelectableNamesAreUnique() {
        let names = AppIconChoice.allCases.compactMap(\.alternateIconName)
        let previews = AppIconChoice.allCases.compactMap(\.previewImageName)
        XCTAssertEqual(Set(names).count, 9)
        XCTAssertEqual(Set(previews).count, 9)
    }

    func testExactlyTheSelectableIconsAreRegisteredAndHaveBundledPreviews() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        XCTAssertEqual(Set(alternates.keys), Set(AppIconChoice.allCases.compactMap(\.alternateIconName)))
        for choice in AppIconChoice.allCases where choice != .system {
            let name = try XCTUnwrap(choice.alternateIconName)
            XCTAssertEqual(AppIconChoice.resolved(from: name), choice)
            XCTAssertTrue(choice.matches(alternateIconName: name))
            let preview = try XCTUnwrap(choice.previewImageName)
            XCTAssertNotNil(UIImage(named: preview), "\(preview) must be bundled for Settings")
        }
    }
}
