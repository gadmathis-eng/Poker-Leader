import SwiftUI

struct TableView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                PokerTableGraphic(lineWidth: 3, innerLineWidth: 2)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 48)
            }
            .navigationTitle("Table")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
