#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIKit "Login with Sarv" button (hosts `SarvLoginButtonView`). Add a
/// `.primaryActionTriggered` / `.touchUpInside` target and call
/// `SarvAuthClient.signIn()` from it.
public final class SarvLoginButton: UIControl {

    public var title = "Login with Sarv" { didSet { render() } }
    public var variant: SarvButtonVariant = .brand { didSet { render() } }
    public var size: SarvButtonSize = .medium { didSet { render(); invalidateIntrinsicContentSize() } }
    public var theme: SarvButtonTheme = .auto { didSet { render() } }
    public override var isEnabled: Bool { didSet { render() } }

    private let host = UIHostingController(rootView: AnyView(EmptyView()))

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = false
        render()
    }

    private func render() {
        let view = SarvLoginButtonView(title, variant: variant, size: size, theme: theme, fullWidth: true) { [weak self] in
            self?.sendActions(for: [.touchUpInside, .primaryActionTriggered])
        }
        .disabled(!isEnabled)
        host.rootView = AnyView(view)
    }

    public override var intrinsicContentSize: CGSize {
        let fitting = host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
        return CGSize(width: ceil(fitting.width), height: size.height)
    }
}
#endif
