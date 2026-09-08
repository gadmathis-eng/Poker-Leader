import SwiftUI

/// How the player pays for their seat: out of the Vault.
///
/// The Vault balance shown here is the player's own and goes no further than
/// this screen — the other people at the table learn only what lands in front of
/// the seat. If the Vault is short, the sheet asks them to add money first
/// rather than quietly seating them for less.
struct TableBuyInPaymentSheet: View {
    let inviteCode: String
    let tableName: String
    let requestedAmount: Money
    let tableCurrencyCode: String
    let limits: TableBuyInLimits?
    let playerKey: String
    let displayName: String
    /// Handed the verified receipt. The seat is only taken after this fires.
    let onComplete: (TableBuyInReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared
    @State private var isWorking = false
    @State private var showAddMoney = false
    @State private var errorMessage: String?
    @State private var statusLine: String?

    private var walletCurrencyCode: String { store.currencyCode }
    private var tableCurrency: String {
        limits?.currencyCode ?? tableCurrencyCode
    }

    private var walletCost: Money? {
        VaultFX.convert(requestedAmount, from: tableCurrency, to: walletCurrencyCode)
    }

    private var available: Money { store.summary.available }

    private var vaultCoversIt: Bool {
        guard let walletCost else { return false }
        return available >= walletCost
    }

    private var shortfall: Money {
        guard let walletCost else { return .zero }
        return (walletCost - available).clampedToNonNegative()
    }
    private var showsConversion: Bool {
        VaultFX.normalize(tableCurrency) != VaultFX.normalize(walletCurrencyCode)
    }

    private var isWithinLimits: Bool {
        guard let limits else { return requestedAmount.isPositive }
        return limits.contains(requestedAmount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DemoFundsBadge()

                    buyInCard

                    if let limits {
                        limitsCard(limits)
                    }

                    vaultCard

                    if !vaultCoversIt {
                        VaultNoticeCard(
                            title: walletCost == nil
                                ? "No exchange rate"
                                : "Not enough in your Vault",
                            message: walletCost == nil
                                ? "There is no published rate for this table's currency, so the buy-in cannot be taken from your Vault."
                                : "Add \(shortfall.formatted(currencyCode: walletCurrencyCode)) to your Vault, then come back to sit down.",
                            tint: AppTheme.gold,
                            iconName: "exclamationmark.triangle.fill"
                        )
                    }

                    if !isWithinLimits, let limits {
                        VaultNoticeCard(
                            title: "Outside the buy-in range",
                            message: "This table takes between \(limits.minimum.formatted(currencyCode: tableCurrency)) and \(limits.maximum.formatted(currencyCode: tableCurrency)). Go back and change your buy-in.",
                            tint: AppTheme.negative,
                            iconName: "exclamationmark.triangle.fill"
                        )
                    }

                    if let statusLine {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(statusLine)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                            Spacer()
                        }
                        .cardSurface()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if vaultCoversIt {
                        VaultPrimaryButton(
                            title: "Use Vault Balance",
                            systemImage: "lock.fill",
                            isEnabled: isWithinLimits && walletCost != nil,
                            isBusy: isWorking
                        ) {
                            Task { await confirm() }
                        }
                    } else if walletCost != nil {
                        VaultPrimaryButton(
                            title: "Add Money",
                            systemImage: "plus.circle.fill",
                            isEnabled: !isWorking,
                            isBusy: false
                        ) {
                            showAddMoney = true
                        }
                    }

                    Text("You are not seated until the whole buy-in has been verified by the backend. The other players see only the chips in front of you — never your Vault.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Buy in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                        .disabled(isWorking)
                }
            }
        }
        .task {
            await store.load()
        }
        .sheet(isPresented: $showAddMoney) {
            AddMoneySheet()
        }
        .presentationDetents([.large])
    }

    private var buyInCard: some View {
        VStack(spacing: 6) {
            Text("BUYING IN AT \(tableName.uppercased())")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            Text(requestedAmount.formatted(currencyCode: tableCurrency))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if showsConversion, let walletCost {
                Text("That's \(walletCost.formatted(currencyCode: walletCurrencyCode)) from your Vault.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 18)
    }

    private func limitsCard(_ limits: TableBuyInLimits) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MINIMUM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Text(limits.minimum.formatted(currencyCode: tableCurrency))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("MAXIMUM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Text(limits.maximum.formatted(currencyCode: tableCurrency))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
            }
        }
        .cardSurface()
    }

    private var vaultCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR VAULT · PRIVATE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.muted)
                Text(available.formatted(currencyCode: walletCurrencyCode))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(vaultCoversIt ? AppTheme.positive : AppTheme.gold)
                    .monospacedDigit()
                if vaultCoversIt {
                    Text(showsConversion
                        ? "Converts \(walletCost?.formatted(currencyCode: walletCurrencyCode) ?? "—") into \(requestedAmount.formatted(currencyCode: tableCurrency)) on the table"
                        : "Moves \(requestedAmount.formatted(currencyCode: tableCurrency)) from Available into In Play")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                } else if walletCost != nil {
                    Text("\(shortfall.formatted(currencyCode: walletCurrencyCode)) short of this buy-in")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "eye.slash.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .accessibilityLabel("Only you can see this")
        }
        .cardSurface()
    }

    private func confirm() async {
        isWorking = true
        errorMessage = nil
        defer {
            isWorking = false
            statusLine = nil
        }

        do {
            statusLine = "Moving your buy-in onto the table…"
            let receipt = try await store.buyInFromVault(
                inviteCode: inviteCode,
                amount: requestedAmount,
                playerKey: playerKey,
                displayName: displayName
            )
            onComplete(receipt)
            dismiss()
        } catch {
            errorMessage = VaultError.from(error).errorDescription
        }
    }
}
