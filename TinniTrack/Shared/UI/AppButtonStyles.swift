import SwiftUI

struct AppCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(opacity(isPressed: configuration.isPressed))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isEnabled)
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.62 }
        return isPressed ? 0.86 : 1
    }
}

struct AppRoundedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(opacity(isPressed: configuration.isPressed))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isEnabled)
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.62 }
        return isPressed ? 0.86 : 1
    }
}

struct AppCircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && isEnabled ? 0.94 : 1)
            .opacity(opacity(isPressed: configuration.isPressed))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isEnabled)
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.62 }
        return isPressed ? 0.82 : 1
    }
}
