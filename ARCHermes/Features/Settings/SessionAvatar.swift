import SwiftUI

/// Initials and color identify a server without importing or storing photos.
struct SessionAvatar: View {
    let initials: String
    let color: Color
    let foreground: Color
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
