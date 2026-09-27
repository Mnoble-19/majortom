import SwiftUI

public extension View {
    /// Keeps `atBottom` true while the scroll view shows its end, so a live
    /// transcript follows new lines only until you scroll up to reread.
    func trackingBottom(_ atBottom: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height
                >= geometry.contentSize.height - 48
        } action: { _, isAtBottom in
            atBottom.wrappedValue = isAtBottom
        }
    }
}

/// Shown while you have scrolled up in a live transcript.
public struct JumpToLatestButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label("Jump to latest", systemImage: "arrow.down")
                .font(.rounded(14, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Palette.accent, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
