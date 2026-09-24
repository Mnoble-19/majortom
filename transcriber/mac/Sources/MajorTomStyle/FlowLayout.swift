import SwiftUI

/// Wraps its children onto as many rows as it takes. Transcripts need it: each
/// word is its own tappable view, so a line cannot just be a `Text`.
public struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    public init(spacing: CGFloat = 4, lineSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, in: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, in: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified)))
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + lineSpacing))
            }
            var row = rows[rows.count - 1]
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            row.indices.append(index)
            row.xs.append(x)
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
