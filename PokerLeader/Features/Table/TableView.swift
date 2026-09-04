import SwiftUI

struct TableView: View {
    @AppStorage("personalSessionCurrencyCode") private var personalSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInCurrencyCode") private var personalBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInAmount") private var personalBuyInAmountString = ""

    @State private var draftSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var draftBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var draftBuyInText = "0"
    @State private var showingSeatSelection = false

    private var personalBuyInAmount: Decimal? {
        guard !personalBuyInAmountString.isEmpty else { return nil }
        return Decimal(string: personalBuyInAmountString)?.clampedToNonNegative
    }

    private var draftBuyInAmount: Decimal? {
        Decimal(string: draftBuyInText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private var canSaveBuyIn: Bool {
        (draftBuyInAmount ?? 0) > 0
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
                        Text("Track your personal buy-in or join a circle session.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "New session")

                        DualCurrencyBuyInSetup(
                            sessionCurrencyCode: $draftSessionCurrencyCode,
                            buyInCurrencyCode: $draftBuyInCurrencyCode,
                            buyInText: $draftBuyInText
                        )

                        Button {
                            savePersonalBuyIn()
                        } label: {
                            Text("Save buy-in")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canSaveBuyIn ? AppTheme.positive : AppTheme.card)
                                .foregroundStyle(canSaveBuyIn ? AppTheme.contrastText : AppTheme.muted)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSaveBuyIn)
                    }
                    .padding(.horizontal)

                    if let amount = personalBuyInAmount, amount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Session currency")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted)
                                Spacer()
                                Text(personalSessionCurrencyCode)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                            }

                            Text(MoneyFormatting.plain(amount, currencyCode: personalBuyInCurrencyCode))
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.gold)
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

                    VStack(spacing: 14) {
                        Image(systemName: "table.furniture.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.text)

                        Text("No active table")
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)

                        Text("Set your buy-in above, or open a circle to start a group game.")
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
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadDraftValues)
            .navigationDestination(isPresented: $showingSeatSelection) {
                TableSeatSelectionView(
                    buyInAmount: personalBuyInAmount ?? 0,
                    buyInCurrencyCode: personalBuyInCurrencyCode,
                    sessionCurrencyCode: personalSessionCurrencyCode
                )
            }
        }
    }

    private func loadDraftValues() {
        draftSessionCurrencyCode = personalSessionCurrencyCode
        draftBuyInCurrencyCode = personalBuyInCurrencyCode
        draftBuyInText = personalBuyInAmountString.isEmpty
            ? "0"
            : personalBuyInAmountString
    }

    private func savePersonalBuyIn() {
        guard let amount = draftBuyInAmount else { return }
        personalSessionCurrencyCode = draftSessionCurrencyCode
        personalBuyInCurrencyCode = draftBuyInCurrencyCode
        personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue
        showingSeatSelection = true
    }
}
