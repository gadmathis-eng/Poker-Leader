import SwiftUI

/// What the player sees when they stand up: what they sat down with, how the
/// night went, and what the backend put back in their Vault.
///
/// Every figure on this sheet comes from the settlement the backend calculated.
/// The app does not add up chips and does not decide what is owed — it asks to
/// leave, and reads back the answer. The choice at the bottom is only about
/// where the money sits next, because it is already in the Vault by the time
/// this appears.
struct LeaveTableSummarySheet: View {
    let settlement: TableSettlement
    let onCashOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared

    private var tableCurrencyCode: String { settlement.tableCurrencyCode }
    private var vaultCurrencyCode: String {
        settlement.walletCurrencyCode ?? store.currencyCode
    }
    private var returnedToVault: Money {
        settlement.walletReturned ?? settlement.returned
    }

    private var netTint: Color {
        if settlement.net.isZero { return AppTheme.text }
        return settlement.net.isPositive ? AppTheme.positive : AppTheme.negative
    }

    private var headline: String {
        if settlement.net.isPositive { return "You finished up" }
        if settlement.net.isNegative { return "You finished down" }
        return "You finished level"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DemoFundsBadge()

                    VStack(spacing: 6) {
                        Text(headline)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Text(settlement.net.formattedSigned(currencyCode: tableCurrencyCode))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(netTint)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .cardSurface(padding: 20)

                    VStack(spacing: 0) {
                        row("You bought in with", settlement.boughtIn.formatted(currencyCode: tableCurrencyCode))
                        Divider().overlay(AppTheme.cardBorder)
                        row(
                            settlement.net.isNegative ? "Losses" : "Winnings",
                            settlement.net.magnitude.formatted(currencyCode: tableCurrencyCode),
                            tint: netTint
                        )
                        Divider().overlay(AppTheme.cardBorder)
                        row(
                            "Returned to your Vault",
                            returnedToVault.formatted(currencyCode: vaultCurrencyCode),
                            tint: AppTheme.positive,
                            isBold: true
                        )
                    }
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.cardBorder)
                    )

                    if !settlement.referenceCode.isEmpty {
                        Text(settlement.referenceCode)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                            .textSelection(.enabled)
                    }

                    if settlement.alreadySettled {
                        VaultNoticeCard(
                            title: "Already settled",
                            message: "This table was cashed off before, so nothing moved again. These are the figures from that settlement.",
                            tint: AppTheme.muted,
                            iconName: "checkmark.seal"
                        )
                    }

                    VStack(spacing: 10) {
                        VaultPrimaryButton(title: "Keep in Vault", systemImage: "lock.fill") {
                            dismiss()
                        }

                        VaultSecondaryButton(
                            title: "Cash Out",
                            systemImage: "arrow.up.circle",
                            isEnabled: store.summary.withdrawable.isPositive
                        ) {
                            dismiss()
                            onCashOut()
                        }
                    }

                    Text("Your Vault is private. Nobody else at that table saw any of these figures.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Left the table")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await store.load() }
        .presentationDetents([.large])
    }

    private func row(
        _ title: String,
        _ value: String,
        tint: Color = AppTheme.text,
        isBold: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .font(isBold ? .subheadline.weight(.bold) : .subheadline)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(14)
    }
}
