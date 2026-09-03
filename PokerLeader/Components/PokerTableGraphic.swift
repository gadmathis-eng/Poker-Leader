import SwiftUI

struct PokerTableGraphic: View {
    var lineWidth: CGFloat = 2
    var innerLineWidth: CGFloat = 1.25
    var fillTable: Bool = true

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 0.52

            ZStack {
                Ellipse()
                    .stroke(AppTheme.text, lineWidth: lineWidth)
                    .frame(width: width, height: height)

                Ellipse()
                    .stroke(AppTheme.text.opacity(0.85), lineWidth: innerLineWidth)
                    .frame(width: width * 0.76, height: height * 0.72)

                if fillTable {
                    Ellipse()
                        .fill(AppTheme.text.opacity(0.08))
                        .frame(width: width * 0.74, height: height * 0.68)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1.85, contentMode: .fit)
    }
}
