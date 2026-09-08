import SwiftUI

/// Cash Out. Shows what can actually leave, the fee, and what lands.
///
/// Two things are deliberate here. The withdrawable figure is the available
/// balance and nothing else — money on a table, money already reserved for
/// another cash-out, and deposits still settling are all excluded, because none
/// of it is the player's to take yet. And the destination is named as the payout
/// provider's, not Apple Pay: Apple Pay takes payments, it does not send them,
/// so calling it the cash-out method would be a lie.
struct CashOutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var store = VaultStore.shared
    @State private var text = "0"
    @State private var withdrawCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var showCurrencyPicker = false
    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var completed: WithdrawalRequest?

    private var walletCurrencyCode: String { store.currencyCode }
    private var summary: VaultSummary { store.summary }

    private var amount: Money {
        Money(userInput: MoneyAmountKeypad.normalizedText(text)) ?? .zero
    }

    private var walletDebit: Money? {
        VaultFX.convert(amount, from: withdrawCurrencyCode, to: walletCurrencyCode)
    }

    private var showsConversion: Bool {
        VaultFX.normalize(withdrawCurrencyCode) != VaultFX.normalize(walletCurrencyCode)
    }

    private var fee: Money { store.feeForWithdrawal(amount) }
    private var net: Money { store.netForWithdrawal(amount) }

    private var needsIdentityCheck: Bool {
        // Sandbox money is not real, so it does not need a real identity behind
        // it. The moment the build stops being a sandbox, this gate turns on and
        // the backend enforces the same rule again regardless of what the app does.
        !summary.isSandbox && summary.identityStatus != .verified
    }

    private var isAmountValid: Bool {
        guard let walletDebit else { return false }
        return walletDebit >= summary.withdrawalMinimum
            && walletDebit <= summary.withdrawable
            && amount.isPositive
            && fee < amount
            && VaultFX.supports(withdrawCurrencyCode)
    }

    private var confirmationMessage: String {
        let payout = "\(net.formatted(currencyCode: withdrawCurrencyCode)) will be sent to \(VaultProviders.payout.destinationDescription) after a fee of \(fee.formatted(currencyCode: withdrawCurrencyCode))."
        if showsConversion, let walletDebit {
            return "\(payout) Your Vault is charged \(walletDebit.formatted(currencyCode: walletCurrencyCode)). The money leaves your available balance now and is held until the payout is finished."
        }
        return "\(payout) The money leaves your available balance now and is held until the payout is finished."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let completed {
                        requestedCard(completed)
                    } else {
                        DemoFundsBadge()

                        withdrawableCard

                        MoneyAmountKeypad(text: $text)

                        breakdownCard

                        if needsIdentityCheck {
                            identityCard
                        }

                        restrictionsCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.negative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VaultPrimaryButton(
                            title: "Review cash-out",
                            systemImage: "arrow.up.circle.fill",
                            isEnabled: isAmountValid && !needsIdentityCheck,
                            isBusy: isWorking
                        ) {
                            isConfirming = true
                        }
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Cash Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                        .disabled(isWorking)
                }
            }
            .alert("Cash out \(amount.formatted(currencyCode: withdrawCurrencyCode))?", isPresented: $isConfirming) {
                Button("Confirm") { Task { await requestCashOut() } }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .onAppear {
                if CurrencyPreferences.isValidCurrencyCode(preferredCurrencyCode),
                   VaultFX.supports(preferredCurrencyCode) {
                    withdrawCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(preferredCurrencyCode)
                } else {
                    withdrawCurrencyCode = walletCurrencyCode
                }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                CurrencyPickerSheet(
                    selectedCurrencyCode: withdrawCurrencyCode,
                    allowedCurrencyCodes: VaultFX.supportedCurrencyCodes
                ) { code in
                    let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                    guard CurrencyPreferences.isValidCurrencyCode(cleaned), VaultFX.supports(cleaned) else { return }
                    withdrawCurrencyCode = cleaned
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .presentationDetents([.large])
    }

    private var withdrawableCard: some View {
        VStack(spacing: 8) {
            Text("AVAILABLE TO WITHDRAW")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.muted)

            Text(summary.withdrawable.formatted(currencyCode: walletCurrencyCode))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.positive)
                .monospacedDigit()

            HStack {
                Text("Send as")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                CurrencyChipButton(currencyCode: withdrawCurrencyCode) {
                    showCurrencyPicker = true
                }
                .accessibilityLabel("Choose cash-out currency")
            }

            Text("Taking out \(amount.formatted(currencyCode: withdrawCurrencyCode))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            if showsConversion, amount.isPositive, let walletDebit {
                Text("That's \(walletDebit.formatted(currencyCode: walletCurrencyCode)) from your Vault.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 18)
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            breakdownRow("Cash-out amount", amount.formatted(currencyCode: withdrawCurrencyCode))
            Divider().overlay(AppTheme.cardBorder)
            if showsConversion, amount.isPositive, let walletDebit {
                breakdownRow("Taken from Vault", walletDebit.formatted(currencyCode: walletCurrencyCode))
                Divider().overlay(AppTheme.cardBorder)
            }
            breakdownRow("Fee", fee.isZero ? "None" : fee.formatted(currencyCode: withdrawCurrencyCode))
            Divider().overlay(AppTheme.cardBorder)
            breakdownRow(
                "You receive",
                net.formatted(currencyCode: withdrawCurrencyCode),
                tint: AppTheme.positive,
                isBold: true
            )
            Divider().overlay(AppTheme.cardBorder)
            breakdownRow("Sent to", VaultProviders.payout.destinationDescription)
        }
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
    }

    private func breakdownRow(
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

    private var identityCard: some View {
        VaultNoticeCard(
            title: "Verify your identity first",
            message: "Real payouts need a verified identity and a verified payout method on file. Identity is currently \(summary.identityStatus.label.lowercased()) and your payout method is \(summary.payoutMethodStatus.label.lowercased()).",
            tint: AppTheme.gold,
            iconName: "person.badge.shield.checkmark"
        )
    }

    private var restrictionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What cannot be withdrawn")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.text)

            restrictionLine("Money in play", summary.inPlay)
            restrictionLine("Deposits still settling", summary.pendingDeposits)
            restrictionLine("Already being withdrawn", summary.pendingWithdrawals)

            Text("Disputed, restricted, or otherwise unavailable money is held back by the backend as well.")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func restrictionLine(_ title: String, _ value: Money) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value.formatted(currencyCode: walletCurrencyCode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(value.isZero ? AppTheme.muted : AppTheme.gold)
                .monospacedDigit()
        }
    }

    private func requestedCard(_ request: WithdrawalRequest) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.gold)

            Text("Cash-out \(request.status.label.lowercased())")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.text)

            Text("\(request.net.formatted(currencyCode: request.currencyCode)) is on its way to \(VaultProviders.payout.destinationDescription). You will see it move through pending, completed, rejected, canceled or failed in your transaction history.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            Text(request.referenceCode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.muted)
                .textSelection(.enabled)

            DemoFundsBadge()

            VaultPrimaryButton(title: "Done") { dismiss() }
        }
        .padding(.top, 24)
    }

    private func requestCashOut() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            completed = try await store.requestCashOut(amount, currencyCode: withdrawCurrencyCode)
        } catch {
            errorMessage = VaultError.from(error).errorDescription
        }
    }
}
