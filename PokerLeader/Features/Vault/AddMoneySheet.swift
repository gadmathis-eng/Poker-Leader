import SwiftUI

/// Add Money. Pick an amount, confirm through Apple Pay, and wait for the
/// backend to say the payment cleared.
///
/// The wait is the point of the third state below. The app does not add the
/// money when the payment sheet closes — it shows "Verifying with the backend"
/// until the deposit has actually been settled server-side, because that is the
/// only moment the balance really changed.
struct AddMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared
    @State private var text = "0"
    @State private var selectedSuggestion: Money?
    @State private var phase: Phase = .choosing
    @State private var errorMessage: String?
    @State private var confirmedAmount: Money?

    private enum Phase: Equatable {
        case choosing
        case authorizing
        case verifying
        case done
    }

    private var currencyCode: String { store.currencyCode }

    private var amount: Money {
        Money(userInput: MoneyAmountKeypad.normalizedText(text)) ?? .zero
    }

    private var suggestions: [Money] {
        [Money(cents: 2_000), Money(cents: 5_000), Money(cents: 10_000)]
    }

    private var isAmountValid: Bool {
        amount >= store.summary.depositMinimum && amount <= store.summary.depositMaximum
    }

    private var isBusy: Bool {
        phase == .authorizing || phase == .verifying
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if phase == .done {
                        successCard
                    } else {
                        DemoFundsBadge()

                        amountCard

                        SuggestedAmountRow(
                            amounts: suggestions,
                            currencyCode: currencyCode,
                            selection: $selectedSuggestion
                        ) { picked in
                            text = NSDecimalNumber(decimal: picked.decimalValue).stringValue
                        }

                        MoneyAmountKeypad(text: $text)
                            .onChange(of: text) { _, _ in
                                selectedSuggestion = suggestions.first { $0 == amount }
                            }

                        limitsLine

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.negative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isBusy {
                            progressCard
                        }

                        VaultPrimaryButton(
                            title: "Confirm with Apple Pay",
                            systemImage: "apple.logo",
                            isEnabled: isAmountValid,
                            isBusy: isBusy
                        ) {
                            Task { await deposit() }
                        }

                        Text("Apple Pay is simulated in this build. The money is added to your Vault only after the backend verifies the payment — never because this app said so.")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Add Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                        .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var amountCard: some View {
        VStack(spacing: 8) {
            Text("ADD TO YOUR VAULT")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.muted)

            Text(amount.formatted(currencyCode: currencyCode))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("Available now: \(store.summary.available.formatted(currencyCode: currencyCode))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 18)
    }

    private var limitsLine: some View {
        Text("Between \(store.summary.depositMinimum.formatted(currencyCode: currencyCode)) and \(store.summary.depositMaximum.formatted(currencyCode: currencyCode)) per deposit.")
            .font(.caption2)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(phase == .authorizing
                ? "Waiting for Apple Pay…"
                : "Verifying the payment with the backend…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            Spacer()
        }
        .cardSurface()
    }

    private var successCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.positive)

            Text("\(confirmedAmount?.formatted(currencyCode: currencyCode) ?? "") added")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.text)

            Text("The backend verified the payment and your Vault has been credited.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            DemoFundsBadge()

            VaultBalanceTile(
                title: "Available",
                amount: store.summary.available,
                currencyCode: currencyCode,
                tint: AppTheme.positive
            )

            VaultPrimaryButton(title: "Done") { dismiss() }
        }
        .padding(.top, 24)
    }

    private func deposit() async {
        errorMessage = nil
        phase = .authorizing

        let requested = amount
        // The provider step and the settlement step both live inside `addMoney`.
        // This timer only moves the label on from "Waiting for Apple Pay" to
        // "Verifying" while that runs; it decides nothing.
        let label = Task {
            try? await Task.sleep(for: .milliseconds(900))
            if phase == .authorizing { phase = .verifying }
        }
        defer { label.cancel() }

        do {
            _ = try await store.addMoney(requested)
            confirmedAmount = requested
            phase = .done
        } catch {
            errorMessage = VaultError.from(error).errorDescription
            phase = .choosing
        }
    }
}
