import SwiftUI

struct TableView: View {
    @AppStorage("personalBuyInCurrencyCode") private var personalBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInAmount") private var personalBuyInAmountString = ""

    @State private var showingPersonalSession = false

    private var personalBuyInAmount: Decimal? {
        guard !personalBuyInAmountString.isEmpty else { return nil }
        return Decimal(string: personalBuyInAmountString)?.clampedToNonNegative
    }

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

                    Button {
                        showingPersonalSession = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.positive)
                            Text("New session")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(16)
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .stroke(AppTheme.cardBorder)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    if let amount = personalBuyInAmount, amount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "My buy-in")
                                .padding(.horizontal)

                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Personal buy-in")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.muted)
                                    Text(MoneyFormatting.plain(amount, currencyCode: personalBuyInCurrencyCode))
                                        .font(.title2.bold())
                                        .foregroundStyle(AppTheme.gold)
                                }
                                Spacer()
                                Button {
                                    showingPersonalSession = true
                                } label: {
                                    Text("Edit")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.positive)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.positive.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(16)
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(AppTheme.cardBorder)
                            )
                            .padding(.horizontal)
                        }
                    }

                    VStack(spacing: 14) {
                        Image("PokerTableIcon")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundStyle(AppTheme.text)

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
            .sheet(isPresented: $showingPersonalSession) {
                PersonalSessionSheet(
                    initialCurrencyCode: personalBuyInCurrencyCode,
                    initialBuyIn: personalBuyInAmount ?? 0
                ) { code, amount in
                    personalBuyInCurrencyCode = code
                    personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue
                }
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
