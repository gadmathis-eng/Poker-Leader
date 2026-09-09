import SwiftUI

/// How the player pays for their seat: out of the Vault, or straight through
/// Apple Pay.
///
/// The Vault balance shown here is the player's own and goes no further than
/// this screen — the other people at the table learn only what lands in front of
/// the seat. If the Vault is short, the sheet offers to make up the difference
/// or pay the whole buy-in by card rather than quietly seating them for less.
struct TableBuyInPaymentSheet: View {
    let inviteCode: String
    let tableName: String
    let requestedAmount: Money
    let limits: TableBuyInLimits?
    let playerKey: String
    let displayName: String
    /// Handed the verified receipt. The seat is only taken after this fires.
    let onComplete: (TableBuyInReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared
    @State private var method: Method = .vault
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusLine: String?

    private enum Method: Hashable {
        case vault
        case applePay
        /// The Vault covers part of it; Apple Pay is asked for the rest. The
        /// backend still sees two separate verified movements.
        case topUp
    }

    private var currencyCode: String { store.currencyCode }
    private var available: Money { store.summary.available }

    private var vaultCoversIt: Bool { available >= requestedAmount }
    private var shortfall: Money { (requestedAmount - available).clampedToNonNegative() }

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

                    methodPicker

                    if !isWithinLimits, let limits {
                        VaultNoticeCard(
                            title: "Outside the buy-in range",
                            message: "This table takes between \(limits.minimum.formatted(currencyCode: currencyCode)) and \(limits.maximum.formatted(currencyCode: currencyCode)). Go back and change your buy-in.",
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

                    VaultPrimaryButton(
                        title: confirmTitle,
                        systemImage: method == .vault ? "lock.fill" : "apple.logo",
                        isEnabled: isWithinLimits,
                        isBusy: isWorking
                    ) {
                        Task { await confirm() }
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
            method = vaultCoversIt ? .vault : (available.isPositive ? .topUp : .applePay)
        }
        .presentationDetents([.large])
    }

    private var confirmTitle: String {
        switch method {
        case .vault: "Use Vault Balance"
        case .applePay: "Pay with Apple Pay"
        case .topUp: "Use Vault + Apple Pay"
        }
    }

    private var buyInCard: some View {
        VStack(spacing: 6) {
            Text("BUYING IN AT \(tableName.uppercased())")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            Text(requestedAmount.formatted(currencyCode: currencyCode))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
                Text(limits.minimum.formatted(currencyCode: currencyCode))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("MAXIMUM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Text(limits.maximum.formatted(currencyCode: currencyCode))
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
                Text(available.formatted(currencyCode: currencyCode))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(vaultCoversIt ? AppTheme.positive : AppTheme.gold)
                    .monospacedDigit()
                if !vaultCoversIt {
                    Text("\(shortfall.formatted(currencyCode: currencyCode)) short of this buy-in")
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

    private var methodPicker: some View {
        VStack(spacing: 10) {
            methodRow(
                .vault,
                title: "Use Vault Balance",
                subtitle: vaultCoversIt
                    ? "Moves \(requestedAmount.formatted(currencyCode: currencyCode)) from Available into In Play"
                    : "Not enough in your Vault for this buy-in",
                isEnabled: vaultCoversIt,
                icon: "lock.fill"
            )

            if !vaultCoversIt && available.isPositive {
                methodRow(
                    .topUp,
                    title: "Use Vault + Apple Pay",
                    subtitle: "Add the missing \(shortfall.formatted(currencyCode: currencyCode)) to your Vault, then buy in with the full \(requestedAmount.formatted(currencyCode: currencyCode))",
                    isEnabled: true,
                    icon: "rectangle.split.2x1.fill"
                )
            }

            methodRow(
                .applePay,
                title: "Pay with Apple Pay",
                subtitle: "The full \(requestedAmount.formatted(currencyCode: currencyCode)) goes straight onto the table",
                isEnabled: true,
                icon: "apple.logo"
            )
        }
    }

    private func methodRow(
        _ value: Method,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        icon: String
    ) -> some View {
        Button {
            guard isEnabled else { return }
            method = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(method == value ? AppTheme.positive : AppTheme.background)
                    .foregroundStyle(method == value ? AppTheme.contrastText : AppTheme.muted)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEnabled ? AppTheme.text : AppTheme.muted)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if method == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.positive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func confirm() async {
        isWorking = true
        errorMessage = nil
        defer {
            isWorking = false
            statusLine = nil
        }

        do {
            let receipt: TableBuyInReceipt

            switch method {
            case .vault:
                statusLine = "Moving your buy-in onto the table…"
                receipt = try await store.buyInFromVault(
                    inviteCode: inviteCode,
                    amount: requestedAmount,
                    playerKey: playerKey,
                    displayName: displayName
                )

            case .applePay:
                statusLine = "Verifying the payment with the backend…"
                receipt = try await store.buyInWithApplePay(
                    inviteCode: inviteCode,
                    amount: requestedAmount,
                    playerKey: playerKey,
                    displayName: displayName
                )

            case .topUp:
                // Top the Vault up first, then buy in once for the whole amount.
                // Splitting the buy-in itself would not work: a table's minimum
                // applies to each buy-in, so the small remainder would be turned
                // away on its own. Doing it this way also means a declined card
                // leaves the player's own money untouched in their Vault rather
                // than stranded halfway onto a table.
                let missing = shortfall
                statusLine = "Topping up your Vault with Apple Pay…"
                _ = try await store.addMoney(missing)

                statusLine = "Moving your buy-in onto the table…"
                receipt = try await store.buyInFromVault(
                    inviteCode: inviteCode,
                    amount: requestedAmount,
                    playerKey: playerKey,
                    displayName: displayName
                )
            }

            onComplete(receipt)
            dismiss()
        } catch {
            errorMessage = VaultError.from(error).errorDescription
        }
    }
}
