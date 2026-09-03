import SwiftUI

struct TableView: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .background(AppTheme.background)
                .navigationTitle("Table")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
