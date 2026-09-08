import SwiftUI

/// The Vault tab in Settings.
///
/// Everything on this screen belongs to the person reading it and reaches no
/// further: the backend will only hand these figures to the account they belong
/// to, and there is no path in the app that shows one player another player's
/// vault. What other people at a table can see is a seat's chips, which is a
/// different number served by a different function.
struct VaultTabView: View {
    @State private var store = VaultStore.shared
    @State private var showAddMoney = false
    @State private var showCashOut = false
    @State private var showAllTransactions = false
    @State private var authManager = SupabaseAuthManager.shared

    private var summary: VaultSummary { store.summary }
    private var currencyCode: String { store.currencyCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.isSandbox {
                VaultNoticeCard(
                    title: "Test Mode",
                    message: "Every figure here is demo money. No card is charged, no deposit is taken, and no payout is made. Add Money credits a sandbox deposit so the flow can be walked through before a payment provider is connected.",
                    tint: AppTheme.gold,
                    iconName: "testtube.2"
                )
            }

            if !store.isCloudBacked {
                VaultNoticeCard(
                    title: "Local demo vault",
                    message: "This device is not signed in to cloud sync, so the demo ledger is running inside the app. Sign in to move it to the backend, where the balances actually belong.",
                    tint: AppTheme.muted,
                    iconName: "icloud.slash"
                )
            }

            balances

            actions

            complianceSection

            transactionsSection
        }
        .task {
            await store.load()
        }
        .onChange(of: authManager.isSignedIn) { _, _ in
            store.refresh()
        }
        .sheet(isPresented: $showAddMoney, onDismiss: store.refresh) {
            AddMoneySheet()
        }
        .sheet(isPresented: $showCashOut, onDismiss: store.refresh) {
            CashOutSheet()
        }
        .sheet(isPresented: $showAllTransactions) {
            VaultTransactionHistoryView(transactions: store.transactions, currencyCode: currencyCode)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Vault")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text("Private to you. Nobody else can see any of this.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var balances: some View {
        VStack(spacing: 12) {
            VaultBalanceTile(
                title: "Total Vault Balance",
                amount: summary.total,
                currencyCode: currencyCode,
                tint: AppTheme.text,
                isPrimary: true,
                footnote: "Available, in play, and anything still settling"
            )

            HStack(spacing: 12) {
                VaultBalanceTile(
                    title: "Available",
                    amount: summary.available,
                    currencyCode: currencyCode,
                    tint: AppTheme.positive,
                    footnote: "Ready to play or cash out"
                )
                VaultBalanceTile(
                    title: "Money In Play",
                    amount: summary.inPlay,
                    currencyCode: currencyCode,
                    tint: AppTheme.gold,
                    footnote: "On a table right now"
                )
            }

            HStack(spacing: 12) {
                VaultBalanceTile(
                    title: "Pending Deposits",
                    amount: summary.pendingDeposits,
                    currencyCode: currencyCode,
                    tint: AppTheme.muted,
                    footnote: "Waiting on the backend to verify"
                )
                VaultBalanceTile(
                    title: "Pending Withdrawals",
                    amount: summary.pendingWithdrawals,
                    currencyCode: currencyCode,
                    tint: AppTheme.muted,
                    footnote: "Reserved, on its way out"
                )
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                VaultPrimaryButton(title: "Add Money", systemImage: "plus.circle.fill") {
                    showAddMoney = true
                }
                VaultSecondaryButton(
                    title: "Cash Out",
                    systemImage: "arrow.up.circle",
                    isEnabled: summary.withdrawable.isPositive
                ) {
                    showCashOut = true
                }
            }

            if !summary.withdrawable.isPositive {
                Text("Money on a table or already being withdrawn cannot be cashed out.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var complianceSection: some View {
        if !store.pendingWithdrawalRequests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Cash-outs in progress")

                ForEach(store.pendingWithdrawalRequests) { request in
                    PendingWithdrawalRow(request: request)
                }
            }
        }

        if summary.isSelfExcluded, let until = summary.selfExcludedUntil {
            VaultNoticeCard(
                title: "Self-exclusion is on",
                message: "You asked us to stop you depositing and playing until \(VaultDateFormatting.dateAndTime(until)). Cashing out is still open to you.",
                tint: AppTheme.negative,
                iconName: "hand.raised.fill"
            )
        }

        if summary.accountStatus != .active {
            VaultNoticeCard(
                title: "This account is \(summary.accountStatus.rawValue)",
                message: "Contact support to sort this out. Money already in your Vault stays yours.",
                tint: AppTheme.negative,
                iconName: "exclamationmark.triangle.fill"
            )
        }
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Transaction history")
                if store.transactions.count > 6 {
                    Button("See all") { showAllTransactions = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.positive)
                }
            }

            if store.transactions.isEmpty {
                Text(store.hasLoadedOnce
                    ? "Nothing here yet. Add money to get started."
                    : "Loading…")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.transactions.prefix(6).enumerated()), id: \.element.id) { index, item in
                        VaultTransactionRow(transaction: item)
                        if index < min(store.transactions.count, 6) - 1 {
                            Divider().overlay(AppTheme.cardBorder)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.cardBorder)
                )
            }
        }
    }
}

private struct PendingWithdrawalRow: View {
    let request: WithdrawalRequest
    @State private var store = VaultStore.shared
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.amount.formatted(currencyCode: request.currencyCode))
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("\(request.net.formatted(currencyCode: request.currencyCode)) to \(VaultProviders.payout.destinationDescription)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                    Text(request.referenceCode)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Text(request.status.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.gold.opacity(0.14))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Button("Cancel") {
                    Task { await run { try await store.cancelCashOut(request.id) } }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.negative)

                Spacer()

                if request.isDemo {
                    // Only exists in the demo. A real payout finishes when the
                    // provider says it has, not when the player taps anything.
                    Button("Simulate payout") {
                        Task { await run { try await store.settleCashOutInSandbox(request.id) } }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.positive)
                }
            }
            .disabled(isWorking)
        }
        .cardSurface()
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        try? await work()
    }
}

struct VaultTransactionHistoryView: View {
    let transactions: [VaultTransaction]
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(transactions) { item in
                        VaultTransactionRow(transaction: item)
                        Divider().overlay(AppTheme.cardBorder)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(AppTheme.background)
            .navigationTitle("Transaction history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
