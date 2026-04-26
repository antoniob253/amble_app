import SwiftUI

struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptic { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == Pressable {
    static var pressable: Pressable { Pressable() }
}

struct PressableCardStyle: ButtonStyle {
    var cornerRadius: CGFloat = 24
    var shadowColor: Color = .black.opacity(0.06)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: shadowColor, radius: configuration.isPressed ? 2 : 10, x: 0, y: configuration.isPressed ? 1 : 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}
