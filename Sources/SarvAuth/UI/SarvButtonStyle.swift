import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Looks of the "Login with Sarv" button — the web SDK's design tokens
/// (`sarv_theme`), so native and web buttons match.
public enum SarvButtonVariant: Sendable {
    /// Filled Sarv blue — the default.
    case brand
    /// White / dark with a border, for screens that already have a primary action.
    case surface
}

public enum SarvButtonSize: Sendable {
    case small, medium, large

    var height: CGFloat { switch self { case .small: 30; case .medium: 38; case .large: 44 } }
    var fontSize: CGFloat { switch self { case .small: 12; case .medium: 13; case .large: 14 } }
    var iconSize: CGFloat { switch self { case .small: 18; case .medium: 24; case .large: 28 } }
    var horizontalPadding: CGFloat { switch self { case .small: 12; case .medium: 16; case .large: 20 } }
}

public enum SarvButtonTheme: Sendable {
    /// Follows the system / app appearance.
    case auto, light, dark
}

struct SarvPalette {
    let brand: Color
    let brandStrong: Color
    let surface: Color
    let border: Color
    let ink: Color

    static let light = SarvPalette(brand: Color(hex: 0x3069B0), brandStrong: Color(hex: 0x275695),
                                   surface: Color(hex: 0xFFFFFF), border: Color(hex: 0xE6E9F1),
                                   ink: Color(hex: 0x2A3450))
    static let dark = SarvPalette(brand: Color(hex: 0x5B92D2), brandStrong: Color(hex: 0x84B0E0),
                                  surface: Color(hex: 0x131826), border: Color(hex: 0x232838),
                                  ink: Color(hex: 0xD8DDE9))

    static func resolve(_ theme: SarvButtonTheme, colorScheme: ColorScheme) -> SarvPalette {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return colorScheme == .dark ? .dark : .light
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum SarvAuthResources {
    /// SwiftPM bundles resources as `Bundle.module`; CocoaPods ships the
    /// `SarvAuth.bundle` resource bundle next to the code.
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: BundleToken.self)
        if let url = host.url(forResource: "SarvAuth", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return host
        #endif
    }()

    private final class BundleToken {}
}

extension Image {
    /// The Sarv mark (vector).
    static var sarvMark: Image { Image("SarvMark", bundle: SarvAuthResources.bundle) }
}
