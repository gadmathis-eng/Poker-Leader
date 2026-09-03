import SwiftUI

struct PokerTableGraphic: View {
    var lineWidth: CGFloat = 2
    var innerLineWidth: CGFloat = 1.25

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 0.52

            ZStack {
                Ellipse()
                    .stroke(Color.primary, lineWidth: lineWidth)
                    .frame(width: width, height: height)

                Ellipse()
                    .stroke(Color.primary.opacity(0.85), lineWidth: innerLineWidth)
                    .frame(width: width * 0.76, height: height * 0.72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1.85, contentMode: .fit)
    }
}

#Preview {
    PokerTableGraphic()
        .padding(40)
}
