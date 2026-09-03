import SwiftUI

struct TableView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Live poker")
                        Text("Table")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Active games and buy-in tracking live here.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 14) {
                        Image("PokerTableIcon")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .foregroundStyle(AppTheme.positive.opacity(0.85))

                        Text("No active table")
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)

                        Text("Open a circle and start a session to track buy-ins at the table.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.cardBorder)
                    )
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(AppTheme.background)
        }
    }
}
