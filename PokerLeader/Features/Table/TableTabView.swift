import SwiftUI

struct TableTabView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Live table")
                        Text("Table")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .background(AppTheme.background)
        }
    }
}
