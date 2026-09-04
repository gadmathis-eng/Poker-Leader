import SwiftUI

struct LaunchIconSplash: View {
    @State private var isVisible = true

    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    Color(red: 14 / 255, green: 14 / 255, blue: 13 / 255)
                        .ignoresSafeArea()
                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.28), value: isVisible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                isVisible = false
            }
        }
    }
}
