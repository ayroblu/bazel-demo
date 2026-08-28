import SwiftUI

struct FuriganaText: View {
  let source: String

  var body: some View {
    WrappingRow(spacing: 0, lineSpacing: 8) {
      ForEach(Array(FuriganaParser.breakableUnits(source).enumerated()), id: \.offset) { _, unit in
        HStack(alignment: .bottom, spacing: 0) {
          ruby(unit.base, reading: unit.reading, emphasized: unit.emphasized)
          if !unit.trailing.isEmpty {
            ruby(unit.trailing, reading: nil, emphasized: unit.emphasized)
          }
        }
        .fixedSize()
      }
    }
    .multilineTextAlignment(.center)
  }

  /// A reading sits above its base characters only, so trailing kana keep a blank line above.
  private func ruby(_ base: String, reading: String?, emphasized: Bool) -> some View {
    VStack(spacing: 1) {
      Text(reading ?? " ")
        .font(.system(size: 24, weight: emphasized ? .bold : .regular))
        .foregroundStyle(.secondary)
      Text(base)
        .font(.system(size: 42, weight: emphasized ? .heavy : .medium))
        .underline(emphasized)
    }
  }
}

/// Lays subviews out left to right, wrapping to a new line when the proposed width runs out.
private struct WrappingRow: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = layoutLines(maxWidth: proposal.width ?? .infinity, subviews: subviews)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var y = bounds.minY
    for line in layoutLines(maxWidth: bounds.width, subviews: subviews) {
      var x = bounds.minX + (bounds.width - line.width) / 2
      for index in line.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + line.height - size.height),
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private struct Line {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func layoutLines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
    var lines: [Line] = []
    var current = Line()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if !current.indices.isEmpty, added > maxWidth {
        lines.append(current)
        current = Line()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { lines.append(current) }
    return lines
  }
}
