import SwiftUI

/// SwiftUI "Login with Sarv" button. It only draws and reports taps — call
/// `SarvAuthClient.signIn()` from `action`.
///
/// ```swift
/// SarvLoginButtonView { Task { try await sarv.signIn() } }
/// ```
public struct SarvLoginButtonView: View {
    private let title: String
    private let variant: SarvButtonVariant
    private let size: SarvButtonSize
    private let theme: SarvButtonTheme
    private let fullWidth: Bool
    private let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String = "Login with Sarv",
                variant: SarvButtonVariant = .brand,
                size: SarvButtonSize = .medium,
                theme: SarvButtonTheme = .auto,
                fullWidth: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.size = size
        self.theme = theme
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image.sarvMark
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.iconSize, height: size.iconSize)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: size.fontSize, weight: .bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
        }
        .buttonStyle(SarvButtonStyle(variant: variant, palette: SarvPalette.resolve(theme, colorScheme: colorScheme)))
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
    }
}

struct SarvButtonStyle: ButtonStyle {
    let variant: SarvButtonVariant
    let palette: SarvPalette

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundColor(variant == .brand ? .white : palette.ink)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(variant == .brand ? (pressed ? palette.brandStrong : palette.brand) : palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(variant == .surface ? palette.border : .clear, lineWidth: 1)
            )
            .opacity(variant == .surface && pressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}
