import SwiftUI

struct TableView: View {
    @AppStorage("personalSessionCurrencyCode") private var personalSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
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
                        Text("Track your personal buy-in or join a circle session.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    Button {
                        showingPersonalSession = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.contrastText)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("New session")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.contrastText)
                                Text("Set session currency and buy-in amount")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.contrastText.opacity(0.75))
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.contrastText.opacity(0.75))
                        }
                        .padding(16)
                        .background(AppTheme.positive)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    if let amount = personalBuyInAmount, amount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "My buy-in")
                                .padding(.horizontal)

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

                                HStack {
                                    Text("Personal buy-in")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.muted)
                                    Spacer()
                                    Text(MoneyFormatting.plain(amount, currencyCode: personalBuyInCurrencyCode))
                                        .font(.title3.bold())
                                        .foregroundStyle(AppTheme.gold)
                                }

                                Button {
                                    showingPersonalSession = true
                                } label: {
                                    Text("Edit")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.positive)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.positive.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        Image(systemName: "table.furniture.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.text)

                        Text("No active table")
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)

                        Text("Tap New session above to set your buy-in, or open a circle to start a group game.")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New session") {
                        showingPersonalSession = true
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.positive)
                }
            }
            .sheet(isPresented: $showingPersonalSession) {
                PersonalSessionSheet(
                    initialSessionCurrencyCode: personalSessionCurrencyCode,
                    initialBuyInCurrencyCode: personalBuyInCurrencyCode,
                    initialBuyIn: personalBuyInAmount ?? 0
                ) { sessionCode, buyInCode, amount in
                    personalSessionCurrencyCode = sessionCode
                    personalBuyInCurrencyCode = buyInCode
                    personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue
                }
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
