import SwiftUI

struct NotchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : enabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == NotchButtonStyle {
    static var notch: NotchButtonStyle { NotchButtonStyle() }
}

struct NotchPulse: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.3 : 0.8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

extension View {
    func notchPulse() -> some View { modifier(NotchPulse()) }
}
