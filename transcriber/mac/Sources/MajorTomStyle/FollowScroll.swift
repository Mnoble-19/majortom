import SwiftUI

/// A live transcript's scroll view: it follows new lines until you scroll up
/// to reread, and picks up following again once you scroll back to the end
/// or press Jump to latest.
///
/// Only your own scrolling decides that. Working it out from the position
/// alone does not hold up: each new line makes the content taller before the
/// view has caught up, which reads as "scrolled away from the bottom" and
/// switched following off by itself.
public struct FollowingScrollView<Content: View, Trigger: Equatable>: View {
    /// Whatever changes when something new arrives — a line count, the words
    /// still being heard.
    let trigger: Trigger
    let content: Content

    @State private var following = true
    @State private var userScrolling = false

    public init(following trigger: Trigger, @ViewBuilder content: () -> Content) {
        self.trigger = trigger
        self.content = content()
    }

    public var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                content
                Color.clear.frame(height: 1).id(Self.bottom)
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .tracking || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 48
            } action: { _, atBottom in
                if userScrolling { following = atBottom }
            }
            .onChange(of: trigger) { _, _ in
                guard following else { return }
                scroll.scrollTo(Self.bottom, anchor: .bottom)
            }
            .overlay(alignment: .bottom) {
                if !following {
                    JumpToLatestButton {
                        following = true
                        withAnimation { scroll.scrollTo(Self.bottom, anchor: .bottom) }
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: following)
        }
    }

    private static var bottom: String { "following-scroll-bottom" }
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
